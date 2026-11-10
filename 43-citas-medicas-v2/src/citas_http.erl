%%% Handler HTTP (cowboy). API JSON:
%%%   GET    /api/catalogo                 medicos y consultorios
%%%   GET    /api/citas                    lista de citas
%%%   POST   /api/citas                    agenda una cita
%%%   DELETE /api/citas/:id                cancela (y ofrece el hueco a la lista de espera)
%%%   POST   /api/citas/:id/confirmar      confirma
%%%   GET    /api/recordatorios            historial de recordatorios
%%%   GET    /api/espera   POST /api/espera  lista de espera
%%%   POST   /api/medicos/:id/baja|alta    medico enfermo / reincorporado
%%%   GET    /api/estadisticas             indicadores
%%%   POST   /api/simulacion               corre el escenario del enunciado
%%%   POST   /api/simulacion/caos          prueba de caos
%%%   DELETE /api/agenda                   borra todo
-module(citas_http).
-export([init/2]).

init(Req0, Accion) ->
    Metodo = cowboy_req:method(Req0),
    Req = try manejar(Metodo, Accion, Req0)
          catch Clase:Razon:Pila ->
              logger:error("Error en ~p: ~p:~p ~p", [Accion, Clase, Razon, Pila]),
              responder(500, #{error => error_interno}, Req0)
          end,
    {ok, Req, Accion}.

manejar(<<"GET">>, catalogo, Req) ->
    Bajas = citas_agenda:medicos_baja(),
    Ahora = erlang:system_time(second),
    Activas = [C || C <- citas_agenda:listar(), citas_reglas:activa(C)],
    Medicos = [M#{de_baja => lists:member(Id, Bajas),
                  citas_activas => length([x || #{medico := X} <- Activas, X =:= Id])}
               || #{id := Id} = M <- citas_catalogo:medicos()],
    Consultorios = [#{id => Co,
                      citas_activas => length([x || #{consultorio := X} <- Activas, X =:= Co]),
                      en_uso => lists:any(fun(#{consultorio := X, inicio := I} = C) ->
                                                  X =:= Co andalso I =< Ahora andalso Ahora < citas_reglas:fin(C)
                                          end, Activas)}
                    || Co <- citas_catalogo:consultorios()],
    responder(200, #{medicos => Medicos, consultorios => Consultorios}, Req);

manejar(<<"GET">>, citas, Req) ->
    responder(200, #{citas => [a_json(C) || C <- citas_agenda:listar()]}, Req);

manejar(<<"POST">>, citas, Req0) ->
    {ok, Cuerpo, Req} = cowboy_req:read_body(Req0),
    case decodificar(Cuerpo) of
        {ok, Mapa} ->
            case construir(Mapa) of
                {ok, Datos}    -> resultado(citas_agenda:agendar(Datos), 201, fun a_json/1, Req);
                {error, Razon} -> error_json(Razon, Req)
            end;
        {error, Razon} -> responder(400, #{error => Razon}, Req)
    end;

manejar(<<"DELETE">>, cancelar, Req) ->
    con_id(Req, fun(Id) ->
        case citas_agenda:cancelar(Id) of
            {ok, #{reasignada := none}} ->
                responder(200, #{cancelada => Id, hueco_ofrecido_a => null}, Req);
            {ok, #{reasignada := Nueva}} ->
                responder(200, #{cancelada => Id, hueco_ofrecido_a => maps:get(paciente, Nueva),
                                 nueva_cita => a_json(Nueva)}, Req);
            {error, Razon} -> error_json(Razon, Req)
        end
    end);

manejar(<<"POST">>, confirmar, Req) ->
    con_id(Req, fun(Id) ->
        case citas_agenda:confirmar(Id) of
            ok             -> responder(200, #{confirmada => Id}, Req);
            {error, Razon} -> error_json(Razon, Req)
        end
    end);

manejar(<<"GET">>, recordatorios, Req) ->
    Lista = [R#{inicio => fecha(maps:get(inicio, R)), generado => fecha(maps:get(generado, R))}
             || R <- citas_recordatorios:listar()],
    responder(200, #{recordatorios => Lista}, Req);

manejar(<<"GET">>, espera, Req) ->
    Lista = [E#{medico_nombre => citas_catalogo:nombre_medico(maps:get(medico, E))}
             || E <- citas_agenda:listar_espera()],
    responder(200, #{espera => Lista}, Req);

manejar(<<"POST">>, espera, Req0) ->
    {ok, Cuerpo, Req} = cowboy_req:read_body(Req0),
    case decodificar(Cuerpo) of
        {ok, M} ->
            case citas_agenda:agregar_espera(maps:get(<<"paciente">>, M, <<>>),
                                             maps:get(<<"medico">>, M, <<>>)) of
                {ok, E}        -> responder(201, E, Req);
                {error, Razon} -> error_json(Razon, Req)
            end;
        {error, Razon} -> responder(400, #{error => Razon}, Req)
    end;

manejar(<<"POST">>, baja, Req) ->
    case citas_agenda:baja_medico(cowboy_req:binding(id, Req)) of
        {ok, Info}     -> responder(200, Info#{nombre => citas_catalogo:nombre_medico(maps:get(medico, Info))}, Req);
        {error, Razon} -> error_json(Razon, Req)
    end;

manejar(<<"POST">>, alta, Req) ->
    ok = citas_agenda:alta_medico(cowboy_req:binding(id, Req)),
    responder(200, #{reincorporado => cowboy_req:binding(id, Req)}, Req);

manejar(<<"GET">>, estadisticas, Req) ->
    Estados = lists:foldl(fun(#{estado := E}, M) -> maps:update_with(E, fun(V) -> V + 1 end, 1, M) end,
                          #{}, citas_recordatorios:listar()),
    responder(200, (citas_agenda:estadisticas())#{recordatorios => Estados}, Req);

manejar(<<"POST">>, simulacion, Req) ->
    responder(200, citas_sim:correr(), Req);

manejar(<<"POST">>, caos, Req) ->
    responder(200, #{experimentos => citas_sim:caos()}, Req);

manejar(<<"DELETE">>, limpiar, Req) ->
    ok = citas_agenda:limpiar(),
    responder(200, #{limpiada => true}, Req);

manejar(_, _, Req) ->
    responder(405, #{error => metodo_no_permitido}, Req).

%%% ------------------------------------------------------------------

con_id(Req, Fun) ->
    try binary_to_integer(cowboy_req:binding(id, Req)) of
        Id -> Fun(Id)
    catch _:_ -> responder(400, #{error => id_invalido}, Req)
    end.

resultado({ok, Cita}, Codigo, Fmt, Req) -> responder(Codigo, Fmt(Cita), Req);
resultado({error, Razon}, _, _, Req)    -> error_json(Razon, Req).

error_json(Razon, Req) -> responder(codigo(Razon), #{error => Razon}, Req).

codigo(R) when R =:= traslape_medico; R =:= traslape_paciente; R =:= traslape_consultorio;
               R =:= sin_consultorio; R =:= no_cancelable; R =:= no_confirmable;
               R =:= medico_de_baja -> 409;
codigo(no_encontrada) -> 404;
codigo(json_invalido) -> 400;
codigo(_)             -> 422.

decodificar(Cuerpo) ->
    try jsx:decode(Cuerpo, [return_maps]) of
        Mapa when is_map(Mapa) -> {ok, Mapa};
        _ -> {error, json_invalido}
    catch _:_ -> {error, json_invalido}
    end.

construir(Mapa) ->
    case parsear_fecha(maps:get(<<"inicio">>, Mapa, undefined)) of
        {ok, Inicio} ->
            {ok, #{paciente => maps:get(<<"paciente">>, Mapa, <<>>),
                   medico => maps:get(<<"medico">>, Mapa, <<>>),
                   inicio => Inicio,
                   duracion_min => maps:get(<<"duracion_min">>, Mapa, 30),
                   motivo => maps:get(<<"motivo">>, Mapa, <<>>),
                   consultorio => consultorio(maps:get(<<"consultorio">>, Mapa, <<>>))}};
        error -> {error, fecha_invalida}
    end.

consultorio(<<>>)       -> auto;
consultorio(<<"auto">>) -> auto;
consultorio(null)       -> auto;
consultorio(C)          -> C.

%% RFC 3339, p. ej. "2026-11-10T09:00:00Z"
parsear_fecha(Fecha) when is_binary(Fecha) ->
    try {ok, calendar:rfc3339_to_system_time(binary_to_list(Fecha))}
    catch _:_ -> error
    end;
parsear_fecha(_) -> error.

fecha(Epoch) -> list_to_binary(calendar:system_time_to_rfc3339(Epoch, [{offset, "Z"}])).

a_json(#{inicio := I, duracion_min := D, medico := M} = Cita) ->
    Cita#{inicio := fecha(I), fin => fecha(I + D * 60),
          medico_nombre => citas_catalogo:nombre_medico(M)}.

responder(Codigo, Mapa, Req) ->
    cowboy_req:reply(Codigo, #{<<"content-type">> => <<"application/json; charset=utf-8">>},
                     jsx:encode(Mapa), Req).
