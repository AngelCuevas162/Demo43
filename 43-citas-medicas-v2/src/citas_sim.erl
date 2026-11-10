%%% Simulacion del escenario del enunciado y prueba de caos.
%%%   - 10 medicos, 4 consultorios, 200 solicitudes de cita para un dia
%%%     (consultas de 15 min, 56 turnos de 7:00 a 21:00), enviadas EN PARALELO
%%%   - dos pacientes piden el mismo horario en el mismo instante
%%%   - un medico se enferma: se reagendan sus citas
%%%   - 20 % de no-show
-module(citas_sim).
-export([correr/0, correr/1, caos/0, verificar_invariante/0]).

-define(SLOT, 900).        % 15 min
-define(SLOTS_DIA, 56).    % 14 h

correr() -> correr(#{}).

correr(Cfg0) ->
    #{seed := Seed, solicitudes := N, no_show := TasaNS} =
        maps:merge(#{seed => {1, 2, 3}, solicitudes => 200, no_show => 0.20}, Cfg0),
    rand:seed(exsss, Seed),
    ok = citas_agenda:limpiar(),
    Base = base_dia(),
    Medicos = [Id || #{id := Id} <- citas_catalogo:medicos()],
    Reqs = [#{paciente => paciente(I),
              medico => lists:nth(rand:uniform(length(Medicos)), Medicos),
              inicio => Base + (rand:uniform(?SLOTS_DIA) - 1) * ?SLOT,
              duracion_min => 15, motivo => <<"Consulta simulada">>,
              consultorio => auto} || I <- lists:seq(1, N)],
    Resultados = en_paralelo([fun() -> citas_agenda:agendar(R) end || R <- Reqs]),
    Aceptadas = length([x || {ok, _} <- Resultados]),
    Rechazos = contar([R || {error, R} <- Resultados]),
    Carrera = carrera(Base),
    Inv1 = verificar_invariante(),
    Enfermo = medico_enfermo(),
    Inv2 = verificar_invariante(),
    NoShow = no_show(TasaNS),
    #{solicitudes => N,
      aceptadas => Aceptadas,
      rechazadas => Rechazos,
      carrera_mismo_instante => Carrera,
      medico_enfermo => Enfermo,
      no_show => NoShow,
      sin_traslapes_tras_altas => Inv1,
      sin_traslapes_tras_reagendar => Inv2,
      estadisticas => citas_agenda:estadisticas()}.

%% Prueba de caos: mata procesos y comprueba que el sistema se recupera.
caos() ->
    ok = citas_agenda:limpiar(),
    Base = base_dia(),
    [citas_agenda:agendar(#{paciente => paciente(I), medico => <<"m01">>,
                            inicio => Base + I * ?SLOT, duracion_min => 15,
                            motivo => <<"caos">>, consultorio => auto})
     || I <- lists:seq(0, 19)],
    Antes = length(citas_agenda:listar()),

    %% 1) matar la agenda
    A1 = whereis(citas_agenda), R1 = whereis(citas_recordatorios),
    exit(A1, kill),
    A2 = esperar_nuevo(citas_agenda, A1),
    R2 = esperar_nuevo(citas_recordatorios, R1),
    Despues = length(citas_agenda:listar()),
    Exp1 = #{mate => <<"citas_agenda">>,
             esperaba => <<"El supervisor reinicia agenda y recordatorios (rest_for_one) y la agenda recarga sus citas del disco">>,
             ocurrio => #{agenda_reiniciada => A2 =/= A1,
                          recordatorios_reiniciado => R2 =/= R1,
                          citas_antes => Antes, citas_despues => Despues}},

    %% 2) matar recordatorios
    A3 = whereis(citas_agenda), R3 = whereis(citas_recordatorios),
    exit(R3, kill),
    R4 = esperar_nuevo(citas_recordatorios, R3),
    Exp2 = #{mate => <<"citas_recordatorios">>,
             esperaba => <<"Solo se reinicia recordatorios; la agenda sigue intacta">>,
             ocurrio => #{recordatorios_reiniciado => R4 =/= R3,
                          agenda_intacta => whereis(citas_agenda) =:= A3}},

    %% 3) matar la agenda en medio de una rafaga de solicitudes concurrentes
    Rafaga = [fun() -> citas_agenda:agendar(#{paciente => paciente(1000 + I),
                                              medico => <<"m02">>,
                                              inicio => Base + (I rem 10) * ?SLOT,
                                              duracion_min => 15,
                                              motivo => <<"rafaga">>, consultorio => auto}) end
              || I <- lists:seq(1, 100)],
    Padre = self(),
    spawn(fun() -> timer:sleep(5), exit(whereis(citas_agenda), kill), Padre ! matado end),
    Res = en_paralelo(Rafaga),
    receive matado -> ok after 1000 -> ok end,
    esperar_nuevo(citas_agenda, undefined),
    Citas = citas_agenda:listar(),
    Ids = [Id || #{id := Id} <- Citas],
    Exp3 = #{mate => <<"citas_agenda, en medio de 100 solicitudes concurrentes">>,
             esperaba => <<"Algunas solicitudes fallan, pero no quedan traslapes ni ids repetidos">>,
             ocurrio => #{solicitudes_ok => length([x || {ok, _} <- Res]),
                          solicitudes_con_error => length([x || R <- Res, not is_tuple_ok(R)]),
                          sin_traslapes => verificar_invariante(),
                          ids_unicos => length(Ids) =:= length(lists:usort(Ids))}},
    [Exp1, Exp2, Exp3].

is_tuple_ok({ok, _}) -> true;
is_tuple_ok(_)       -> false.

%%% ------------------------------------------------------------------

base_dia() -> ((erlang:system_time(second) + 86400) div 3600) * 3600.

paciente(I) -> iolist_to_binary(["Paciente ", integer_to_list(I)]).

en_paralelo(Funs) ->
    Padre = self(), Ref = make_ref(),
    [spawn(fun() -> Padre ! {Ref, catch F()} end) || F <- Funs],
    [receive {Ref, R} -> R after 15000 -> {error, timeout} end || _ <- Funs].

%% Dos pacientes piden el mismo medico y horario en el mismo instante.
carrera(Base) ->
    T = Base + 60 * ?SLOT,
    Pedir = fun(Pac) ->
                fun() -> citas_agenda:agendar(#{paciente => Pac, medico => <<"m01">>,
                                                inicio => T, duracion_min => 15,
                                                motivo => <<"Carrera">>, consultorio => auto}) end
            end,
    Res = en_paralelo([Pedir(<<"Carrera A">>), Pedir(<<"Carrera B">>)]),
    #{ganadores => length([x || {ok, _} <- Res]),
      rechazados => contar([R || {error, R} <- Res])}.

%% El medico con mas citas se enferma: se reagendan todas sus citas.
medico_enfermo() ->
    Cuenta = contar([M || #{medico := M} = C <- citas_agenda:listar(), citas_reglas:activa(C)]),
    case maps:to_list(Cuenta) of
        [] -> none;
        L  ->
            {Medico, _} = lists:last(lists:keysort(2, L)),
            {ok, Info} = citas_agenda:baja_medico(Medico),
            Info#{nombre => citas_catalogo:nombre_medico(Medico)}
    end.

%% Marca el 20 % (aprox.) de las citas como no-show y el resto como atendidas.
no_show(Tasa) ->
    Activas = [C || C <- citas_agenda:listar(), citas_reglas:activa(C)],
    {NS, At} = lists:foldl(
                 fun(#{id := Id}, {N, A}) ->
                         case rand:uniform() < Tasa of
                             true  -> ok = citas_agenda:marcar(Id, no_show),  {N + 1, A};
                             false -> ok = citas_agenda:marcar(Id, atendida), {N, A + 1}
                         end
                 end, {0, 0}, Activas),
    #{no_show => NS, atendidas => At, tasa_objetivo => Tasa,
      tasa_real => case NS + At of 0 -> 0.0; T -> NS / T end}.

%% Invariante: ninguna pareja de citas que ocupan horario se traslapa.
verificar_invariante() ->
    citas_reglas:sin_traslapes([C || C <- citas_agenda:listar(), citas_reglas:ocupa(C)]).

contar(Lista) ->
    lists:foldl(fun(K, M) -> maps:update_with(K, fun(V) -> V + 1 end, 1, M) end, #{}, Lista).

esperar_nuevo(Nombre, Viejo) -> esperar_nuevo(Nombre, Viejo, 100).
esperar_nuevo(Nombre, _Viejo, 0) -> whereis(Nombre);
esperar_nuevo(Nombre, Viejo, N) ->
    case whereis(Nombre) of
        Pid when is_pid(Pid), Pid =/= Viejo -> timer:sleep(30), Pid;
        _ -> timer:sleep(20), esperar_nuevo(Nombre, Viejo, N - 1)
    end.
