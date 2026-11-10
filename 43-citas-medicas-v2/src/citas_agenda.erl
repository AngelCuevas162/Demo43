%%% gen_server dueno de TODA la agenda (citas, lista de espera, medicos de baja).
%%% Al serializar las altas por un solo proceso, la validacion de traslapes es
%%% atomica. El estado se guarda en disco tras cada cambio, de modo que un
%%% reinicio del proceso (o del nodo) no pierde citas ni recordatorios enviados.
-module(citas_agenda).
-behaviour(gen_server).

-export([start_link/0, agendar/1, cancelar/1, confirmar/1, marcar/2, listar/0,
         agregar_espera/2, listar_espera/0, baja_medico/1, alta_medico/1,
         medicos_baja/0, pendientes_recordatorio/2, marcar_recordatorio/3,
         estadisticas/0, limpiar/0]).
-export([init/1, handle_call/3, handle_cast/2]).

-record(state, {siguiente_id = 1 :: pos_integer(),
                citas  = #{}     :: #{pos_integer() => map()},
                espera = []      :: [map()],
                bajas  = []      :: [binary()],
                archivo          :: undefined | file:filename()}).

%%% ------------------------------------------------------------------
%%% API
%%% ------------------------------------------------------------------

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Datos = #{paciente, medico, inicio, duracion_min, motivo, consultorio | auto}
agendar(Datos)          -> gen_server:call(?MODULE, {agendar, Datos}).
cancelar(Id)            -> gen_server:call(?MODULE, {cancelar, Id}).
confirmar(Id)           -> gen_server:call(?MODULE, {confirmar, Id}).
marcar(Id, Estado)      -> gen_server:call(?MODULE, {marcar, Id, Estado}).
listar()                -> gen_server:call(?MODULE, listar).
agregar_espera(P, M)    -> gen_server:call(?MODULE, {espera, P, M}).
listar_espera()         -> gen_server:call(?MODULE, listar_espera).
baja_medico(M)          -> gen_server:call(?MODULE, {baja, M}).
alta_medico(M)          -> gen_server:call(?MODULE, {alta, M}).
medicos_baja()          -> gen_server:call(?MODULE, bajas).
estadisticas()          -> gen_server:call(?MODULE, estadisticas).
limpiar()               -> gen_server:call(?MODULE, limpiar).

%% Lista de {Cita, Tipo} a las que les toca recordatorio ahora.
pendientes_recordatorio(Ahora, Ventanas) ->
    gen_server:call(?MODULE, {pendientes, Ahora, Ventanas}).

marcar_recordatorio(Id, Tipo, Resultado) ->
    gen_server:cast(?MODULE, {recordatorio, Id, Tipo, Resultado}).

%%% ------------------------------------------------------------------
%%% Callbacks
%%% ------------------------------------------------------------------

init([]) ->
    Archivo = application:get_env(citas_medicas, archivo_datos, undefined),
    {ok, cargar(#state{archivo = Archivo})}.

handle_call({agendar, Datos}, _De, S) ->
    case crear(Datos, S) of
        {ok, Cita, S1}   -> {reply, {ok, Cita}, guardar(S1)};
        {error, _} = Err -> {reply, Err, S}
    end;

handle_call({cancelar, Id}, _De, #state{citas = Citas} = S) ->
    case Citas of
        #{Id := #{estado := E} = Cita} when E =:= programada;
                                           E =:= confirmada;
                                           E =:= reagendar_pendiente ->
            S1 = S#state{citas = Citas#{Id := Cita#{estado := cancelada}}},
            {Reasignada, S2} = ofrecer_hueco(Cita, S1),
            {reply, {ok, #{reasignada => Reasignada}}, guardar(S2)};
        #{Id := _} -> {reply, {error, no_cancelable}, S};
        _          -> {reply, {error, no_encontrada}, S}
    end;

handle_call({confirmar, Id}, _De, #state{citas = Citas} = S) ->
    case Citas of
        #{Id := #{estado := programada} = C} ->
            {reply, ok, guardar(S#state{citas = Citas#{Id := C#{estado := confirmada}}})};
        #{Id := _} -> {reply, {error, no_confirmable}, S};
        _          -> {reply, {error, no_encontrada}, S}
    end;

handle_call({marcar, Id, Nuevo}, _De, #state{citas = Citas} = S)
  when Nuevo =:= atendida; Nuevo =:= no_show ->
    case Citas of
        #{Id := C} ->
            case citas_reglas:activa(C) of
                true  -> {reply, ok, guardar(S#state{citas = Citas#{Id := C#{estado := Nuevo}}})};
                false -> {reply, {error, no_marcable}, S}
            end;
        _ -> {reply, {error, no_encontrada}, S}
    end;

handle_call(listar, _De, #state{citas = Citas} = S) ->
    {reply, ordenar(maps:values(Citas)), S};

handle_call({espera, P, M}, _De, #state{espera = E} = S) when is_binary(P), P =/= <<>>, is_binary(M) ->
    case citas_catalogo:existe_medico(M) of
        true ->
            Entrada = #{paciente => P, medico => M, solicitado => erlang:system_time(second)},
            {reply, {ok, Entrada}, guardar(S#state{espera = E ++ [Entrada]})};
        false ->
            {reply, {error, medico_desconocido}, S}
    end;
handle_call({espera, _, _}, _De, S) ->
    {reply, {error, datos_invalidos}, S};

handle_call(listar_espera, _De, #state{espera = E} = S) ->
    {reply, E, S};

handle_call({baja, M}, _De, #state{citas = Citas} = S) ->
    case citas_catalogo:existe_medico(M) of
        false -> {reply, {error, medico_desconocido}, S};
        true  ->
            Ahora = erlang:system_time(second),
            S1 = S#state{bajas = lists:usort([M | S#state.bajas])},
            Afectadas = [C || #{medico := X, inicio := I} = C <- ordenar(maps:values(Citas)),
                              X =:= M, citas_reglas:activa(C), I > Ahora],
            {S2, Reasig, Pend} = reagendar(Afectadas, S1, 0, 0),
            Info = #{medico => M, afectadas => length(Afectadas),
                     reasignadas => Reasig, pendientes => Pend},
            {reply, {ok, Info}, guardar(S2)}
    end;

handle_call({alta, M}, _De, S) ->
    {reply, ok, guardar(S#state{bajas = lists:delete(M, S#state.bajas)})};

handle_call(bajas, _De, #state{bajas = B} = S) ->
    {reply, B, S};

handle_call({pendientes, Ahora, Ventanas}, _De, #state{citas = Citas} = S) ->
    Pend = lists:append([pendientes_de(C, Ahora, Ventanas)
                         || C <- ordenar(maps:values(Citas)), citas_reglas:activa(C)]),
    {reply, Pend, S};

handle_call(estadisticas, _De, S) ->
    {reply, calcular_estadisticas(S), S};

handle_call(limpiar, _De, S) ->
    {reply, ok, guardar(S#state{siguiente_id = 1, citas = #{}, espera = [], bajas = []})}.

handle_cast({recordatorio, Id, Tipo, Resultado}, #state{citas = Citas} = S) ->
    case Citas of
        #{Id := #{recordatorios := R} = C} ->
            C1 = C#{recordatorios := R#{Tipo => Resultado}},
            {noreply, guardar(S#state{citas = Citas#{Id := C1}})};
        _ -> {noreply, S}
    end.

%%% ------------------------------------------------------------------
%%% Internas
%%% ------------------------------------------------------------------

crear(Datos0, #state{siguiente_id = Id, citas = Citas, bajas = Bajas} = S) ->
    Datos = maps:merge(#{motivo => <<>>}, Datos0),
    Ahora = erlang:system_time(second),
    case citas_reglas:validar(Datos, Ahora, activas(Citas), Bajas) of
        {ok, Consultorio} ->
            Cita = (maps:without([consultorio], Datos))
                       #{id => Id, consultorio => Consultorio,
                         estado => programada, recordatorios => #{}},
            {ok, Cita, S#state{siguiente_id = Id + 1, citas = Citas#{Id => Cita}}};
        {error, _} = Err -> Err
    end.

activas(Citas) -> [C || C <- maps:values(Citas), citas_reglas:activa(C)].

ordenar(Citas) ->
    lists:sort(fun(#{inicio := A, id := IA}, #{inicio := B, id := IB}) -> {A, IA} =< {B, IB} end, Citas).

%% Al cancelar una cita activa, el hueco se ofrece al primero de la lista de
%% espera de ese medico que pueda tomarlo.
ofrecer_hueco(Cita, #state{espera = Espera} = S) ->
    case citas_reglas:activa(Cita) of
        false -> {none, S};
        true  -> asignar_espera(Cita, Espera, [], S)
    end.

asignar_espera(_Cita, [], _Vistos, S) -> {none, S};
asignar_espera(#{medico := M} = Cita, [#{medico := M, paciente := P} = E | Resto], Vistos, S) ->
    Datos = #{paciente => P, medico => M,
              inicio => maps:get(inicio, Cita),
              duracion_min => maps:get(duracion_min, Cita),
              consultorio => maps:get(consultorio, Cita),
              motivo => <<"Hueco liberado (lista de espera)">>},
    case crear(Datos, S) of
        {ok, Nueva, S1} -> {Nueva, S1#state{espera = lists:reverse(Vistos) ++ Resto}};
        {error, _}      -> asignar_espera(Cita, Resto, [E | Vistos], S)
    end;
asignar_espera(Cita, [E | Resto], Vistos, S) ->
    asignar_espera(Cita, Resto, [E | Vistos], S).

%% Reagenda masivamente las citas de un medico que ya no puede atender:
%% las pasa a otro medico libre en ese mismo horario (el menos cargado);
%% si no hay ninguno, quedan "reagendar_pendiente".
reagendar([], S, R, P) -> {S, R, P};
reagendar([#{id := Id} = C | Resto], #state{citas = Citas} = S, R, P) ->
    case buscar_reemplazo(C, S) of
        {ok, Nuevo} ->
            S1 = S#state{citas = Citas#{Id := C#{medico := Nuevo}}},
            reagendar(Resto, S1, R + 1, P);
        none ->
            S1 = S#state{citas = Citas#{Id := C#{estado := reagendar_pendiente}}},
            reagendar(Resto, S1, R, P + 1)
    end.

buscar_reemplazo(#{id := Id, medico := Origen} = C, #state{citas = Citas, bajas = Bajas}) ->
    Otras = [A || #{id := AId} = A <- activas(Citas), AId =/= Id],
    Libres = [M || #{id := M} <- citas_catalogo:medicos(),
                   M =/= Origen, not lists:member(M, Bajas),
                   not lists:any(fun(#{medico := X} = A) ->
                                         X =:= M andalso citas_reglas:se_traslapan(C, A)
                                 end, Otras)],
    Carga = fun(M) -> length([x || #{medico := X} <- Otras, X =:= M]) end,
    case lists:sort(fun(A, B) -> Carga(A) =< Carga(B) end, Libres) of
        []      -> none;
        [M | _] -> {ok, M}
    end.

%% Recordatorios a 48 h y 2 h. Si faltan <= 2 h se manda el de 2 h; si faltan
%% <= 48 h, el de 48 h. "Resuelto" = ya entregado o dado por fallido.
pendientes_de(#{inicio := I, recordatorios := R} = C, Ahora, #{r48 := V48, r2 := V2}) ->
    Falta = I - Ahora,
    if
        Falta =< 0  -> [];
        Falta =< V2 -> pendiente(C, r2, R);
        Falta =< V48 -> pendiente(C, r48, R);
        true        -> []
    end.

pendiente(C, Tipo, R) ->
    case maps:is_key(Tipo, R) of
        true  -> [];
        false -> [{C, Tipo}]
    end.

calcular_estadisticas(#state{citas = Citas, espera = E, bajas = B}) ->
    Todas = maps:values(Citas),
    Ocupan = [C || C <- Todas, citas_reglas:ocupa(C)],
    PorEstado = contar([Es || #{estado := Es} <- Todas]),
    NoShow = maps:get(no_show, PorEstado, 0),
    Atendidas = maps:get(atendida, PorEstado, 0),
    Tasa = case NoShow + Atendidas of
               0 -> 0.0;
               T -> NoShow / T
           end,
    #{total => length(Todas),
      por_estado => PorEstado,
      por_medico => contar([M || #{medico := M} <- Ocupan]),
      por_consultorio => contar([Co || #{consultorio := Co} <- Ocupan]),
      tasa_no_show => Tasa,
      en_espera => length(E),
      medicos_baja => B}.

contar(Lista) ->
    lists:foldl(fun(K, M) -> maps:update_with(K, fun(V) -> V + 1 end, 1, M) end, #{}, Lista).

%%% Persistencia: el estado completo se escribe de forma atomica (tmp + rename).
cargar(#state{archivo = undefined} = S) -> S;
cargar(#state{archivo = Archivo} = S) ->
    case file:read_file(Archivo) of
        {ok, Bin} ->
            try binary_to_term(Bin) of
                #{siguiente_id := Id, citas := C, espera := E, bajas := B} ->
                    S#state{siguiente_id = Id, citas = C, espera = E, bajas = B};
                _ -> S
            catch _:_ -> S
            end;
        {error, _} -> S
    end.

guardar(#state{archivo = undefined} = S) -> S;
guardar(#state{archivo = Archivo} = S) ->
    Dato = #{siguiente_id => S#state.siguiente_id, citas => S#state.citas,
             espera => S#state.espera, bajas => S#state.bajas},
    ok = filelib:ensure_dir(Archivo),
    Tmp = Archivo ++ ".tmp",
    ok = file:write_file(Tmp, term_to_binary(Dato)),
    ok = file:rename(Tmp, Archivo),
    S.
