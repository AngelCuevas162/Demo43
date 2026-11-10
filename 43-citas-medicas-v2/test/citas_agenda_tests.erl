-module(citas_agenda_tests).
-include_lib("eunit/include/eunit.hrl").

-define(M1, <<"m01">>).
-define(M2, <<"m02">>).

%% Manana a esta hora: siempre es futuro y queda fuera de la ventana de 48 h.
base() -> erlang:system_time(second) + 3 * 86400.

cita(Pac, Med, Inicio) -> cita(Pac, Med, Inicio, 30).
cita(Pac, Med, Inicio, Dur) ->
    #{paciente => Pac, medico => Med, inicio => Inicio, duracion_min => Dur,
      motivo => <<"consulta">>, consultorio => auto}.

preparar_env() ->
    application:set_env(citas_medicas, archivo_datos, undefined),
    application:set_env(citas_medicas, prob_fallo_entrega, 0.0),
    application:set_env(citas_medicas, intervalo_ms, 3600000),
    application:set_env(citas_medicas, max_intentos, 3),
    application:set_env(citas_medicas, ventana_r48_seg, 172800),
    application:set_env(citas_medicas, ventana_r2_seg, 7200).

%%% ------------------------------------------------------------------
%%% Reglas de agenda (sin supervisor)
%%% ------------------------------------------------------------------

agenda_test_() ->
    {foreach,
     fun() -> preparar_env(),
              {ok, _} = citas_agenda:start_link(),
              {ok, _} = citas_recordatorios:start_link() end,
     fun(_) -> gen_server:stop(citas_recordatorios), gen_server:stop(citas_agenda) end,
     [fun cita_valida/0,
      fun traslape_medico/0,
      fun traslape_paciente/0,
      fun citas_consecutivas_ok/0,
      fun mismo_horario_otro_medico_otro_consultorio/0,
      fun consultorios_agotados/0,
      fun cancelar_libera_horario/0,
      fun cancelar_ofrece_hueco_a_lista_de_espera/0,
      fun confirmar_cita/0,
      fun datos_invalidos/0,
      fun baja_medico_reagenda/0,
      fun baja_medico_sin_reemplazo/0,
      fun recordatorio_48h_una_sola_vez/0,
      fun recordatorio_2h/0,
      fun no_recuerda_citas_lejanas/0,
      fun entrega_fallida_reintenta_y_marca_fallido/0,
      fun concurrencia_50_mismo_horario/0,
      fun simulacion_del_enunciado/0]}.

cita_valida() ->
    {ok, C} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, base())),
    ?assertMatch(#{id := 1, estado := programada, consultorio := <<"C1">>}, C).

traslape_medico() ->
    B = base(),
    {ok, _} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, B)),
    ?assertEqual({error, traslape_medico}, citas_agenda:agendar(cita(<<"Luis">>, ?M1, B + 600))).

traslape_paciente() ->
    B = base(),
    {ok, _} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, B)),
    ?assertEqual({error, traslape_paciente}, citas_agenda:agendar(cita(<<"Ana">>, ?M2, B + 600))).

citas_consecutivas_ok() ->
    B = base(),
    {ok, _} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, B)),
    %% empieza justo cuando termina la anterior: no hay traslape
    ?assertMatch({ok, _}, citas_agenda:agendar(cita(<<"Luis">>, ?M1, B + 1800))).

mismo_horario_otro_medico_otro_consultorio() ->
    B = base(),
    {ok, #{consultorio := C1}} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, B)),
    {ok, #{consultorio := C2}} = citas_agenda:agendar(cita(<<"Luis">>, ?M2, B)),
    ?assertNotEqual(C1, C2).

consultorios_agotados() ->
    B = base(),
    Meds = [<<"m01">>, <<"m02">>, <<"m03">>, <<"m04">>, <<"m05">>],
    Res = [citas_agenda:agendar(cita(integer_to_binary(N), M, B))
           || {N, M} <- lists:zip(lists:seq(1, 5), Meds)],
    ?assertEqual(4, length([x || {ok, _} <- Res])),
    ?assertEqual({error, sin_consultorio}, lists:last(Res)).

cancelar_libera_horario() ->
    B = base(),
    {ok, #{id := Id}} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, B)),
    ?assertMatch({ok, #{reasignada := none}}, citas_agenda:cancelar(Id)),
    ?assertEqual({error, no_cancelable}, citas_agenda:cancelar(Id)),
    ?assertEqual({error, no_encontrada}, citas_agenda:cancelar(999)),
    ?assertMatch({ok, _}, citas_agenda:agendar(cita(<<"Luis">>, ?M1, B))).

cancelar_ofrece_hueco_a_lista_de_espera() ->
    B = base(),
    {ok, #{id := Id}} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, B)),
    {ok, _} = citas_agenda:agregar_espera(<<"Beto">>, ?M1),
    {ok, #{reasignada := Nueva}} = citas_agenda:cancelar(Id),
    ?assertMatch(#{paciente := <<"Beto">>, inicio := B, estado := programada}, Nueva),
    ?assertEqual([], citas_agenda:listar_espera()).

confirmar_cita() ->
    {ok, #{id := Id}} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, base())),
    ?assertEqual(ok, citas_agenda:confirmar(Id)),
    ?assertEqual({error, no_confirmable}, citas_agenda:confirmar(Id)),
    ?assertMatch([#{estado := confirmada}], citas_agenda:listar()).

datos_invalidos() ->
    B = base(),
    ?assertEqual({error, en_el_pasado}, citas_agenda:agendar(cita(<<"A">>, ?M1, erlang:system_time(second) - 60))),
    ?assertEqual({error, duracion_invalida}, citas_agenda:agendar(cita(<<"A">>, ?M1, B, 1))),
    ?assertEqual({error, datos_incompletos}, citas_agenda:agendar(cita(<<>>, ?M1, B))),
    ?assertEqual({error, medico_desconocido}, citas_agenda:agendar(cita(<<"A">>, <<"zzz">>, B))),
    ?assertEqual({error, datos_invalidos}, citas_agenda:agendar(#{foo => bar})).

baja_medico_reagenda() ->
    B = base(),
    [{ok, _} = citas_agenda:agendar(cita(integer_to_binary(N), ?M1, B + N * 1800)) || N <- lists:seq(0, 4)],
    {ok, Info} = citas_agenda:baja_medico(?M1),
    ?assertMatch(#{afectadas := 5, reasignadas := 5, pendientes := 0}, Info),
    ?assertEqual([], [C || #{medico := ?M1} = C <- citas_agenda:listar()]),
    ?assert(citas_sim:verificar_invariante()),
    ?assertEqual({error, medico_de_baja}, citas_agenda:agendar(cita(<<"Z">>, ?M1, B + 99999))).

baja_medico_sin_reemplazo() ->
    B = base(),
    {ok, _} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, B)),
    [{ok, _} = citas_agenda:baja_medico(M) || #{id := M} <- citas_catalogo:medicos(), M =/= ?M1],
    {ok, Info} = citas_agenda:baja_medico(?M1),
    ?assertMatch(#{afectadas := 1, reasignadas := 0, pendientes := 1}, Info),
    ?assertMatch([#{estado := reagendar_pendiente}], citas_agenda:listar()).

recordatorio_48h_una_sola_vez() ->
    En24h = erlang:system_time(second) + 24 * 3600,
    {ok, _} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, En24h)),
    ok = citas_recordatorios:revisar_ahora(),
    ?assertMatch([#{tipo := r48, estado := entregado, paciente := <<"Ana">>}], citas_recordatorios:listar()),
    ok = citas_recordatorios:revisar_ahora(),
    ?assertEqual(1, length(citas_recordatorios:listar())).

recordatorio_2h() ->
    En1h = erlang:system_time(second) + 3600,
    {ok, _} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, En1h)),
    ok = citas_recordatorios:revisar_ahora(),
    ?assertMatch([#{tipo := r2, estado := entregado}], citas_recordatorios:listar()).

no_recuerda_citas_lejanas() ->
    {ok, _} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, base())),
    ok = citas_recordatorios:revisar_ahora(),
    ?assertEqual([], citas_recordatorios:listar()).

entrega_fallida_reintenta_y_marca_fallido() ->
    application:set_env(citas_medicas, prob_fallo_entrega, 1.0),   % el canal siempre falla
    gen_server:stop(citas_recordatorios), {ok, _} = citas_recordatorios:start_link(),
    En24h = erlang:system_time(second) + 24 * 3600,
    {ok, _} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, En24h)),
    ok = citas_recordatorios:revisar_ahora(),
    ?assertMatch([#{estado := reintentando, intentos := 1}], citas_recordatorios:listar()),
    ok = citas_recordatorios:revisar_ahora(),
    ok = citas_recordatorios:revisar_ahora(),
    ?assertMatch([#{estado := fallido, intentos := 3}], citas_recordatorios:listar()),
    ok = citas_recordatorios:revisar_ahora(),                         % ya no insiste
    ?assertMatch([#{estado := fallido, intentos := 3}], citas_recordatorios:listar()),
    application:set_env(citas_medicas, prob_fallo_entrega, 0.0).

%% 50 procesos piden el MISMO horario del MISMO medico: solo uno gana.
concurrencia_50_mismo_horario() ->
    B = base(), Padre = self(),
    [spawn(fun() -> Padre ! {r, citas_agenda:agendar(cita(integer_to_binary(N), ?M1, B))} end)
     || N <- lists:seq(1, 50)],
    Res = [receive {r, R} -> R end || _ <- lists:seq(1, 50)],
    ?assertEqual(1, length([x || {ok, _} <- Res])),
    ?assertEqual(1, length(citas_agenda:listar())).

simulacion_del_enunciado() ->
    R = citas_sim:correr(),
    ?assertMatch(#{solicitudes := 200}, R),
    ?assert(maps:get(aceptadas, R) > 100),
    ?assertMatch(#{ganadores := 1}, maps:get(carrera_mismo_instante, R)),
    ?assert(maps:get(sin_traslapes_tras_altas, R)),
    ?assert(maps:get(sin_traslapes_tras_reagendar, R)),
    #{no_show := NS} = maps:get(no_show, R),
    ?assert(NS > 0).

%%% ------------------------------------------------------------------
%%% Supervision y persistencia (con el arbol de supervision real)
%%% ------------------------------------------------------------------

supervision_test_() ->
    {foreach,
     fun() -> preparar_env(),
              Archivo = filename:join("/tmp", "citas_test_" ++ integer_to_list(erlang:unique_integer([positive])) ++ ".bin"),
              application:set_env(citas_medicas, archivo_datos, Archivo),
              {ok, Sup} = citas_sup:start_link(), unlink(Sup),
              {Sup, Archivo} end,
     fun({Sup, Archivo}) ->
             Ref = monitor(process, Sup), exit(Sup, shutdown),
             receive {'DOWN', Ref, _, _, _} -> ok after 2000 -> ok end,
             file:delete(Archivo) end,
     [fun(_) ->
          [{"reinicio de la agenda conserva citas (persistencia)", fun reinicio_conserva_citas/0},
           {"reinicio de la agenda: recordatorios pendientes siguen vigentes", fun recordatorios_sobreviven_reinicio/0},
           {"prueba de caos completa", fun prueba_de_caos/0}]
      end]}.

reinicio_conserva_citas() ->
    B = base(),
    {ok, _} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, B)),
    {ok, _} = citas_agenda:agendar(cita(<<"Luis">>, ?M2, B)),
    Pid = whereis(citas_agenda), exit(Pid, kill),
    esperar_nuevo(citas_agenda, Pid),
    ?assertEqual(2, length(citas_agenda:listar())).

recordatorios_sobreviven_reinicio() ->
    En24h = erlang:system_time(second) + 24 * 3600,
    {ok, _} = citas_agenda:agendar(cita(<<"Ana">>, ?M1, En24h)),
    {ok, _} = citas_agenda:agendar(cita(<<"Luis">>, ?M2, En24h + 3600)),
    ok = citas_recordatorios:revisar_ahora(),            % ambos reciben r48
    {ok, _} = citas_agenda:agendar(cita(<<"Nuevo">>, <<"m03">>, En24h)),
    Pid = whereis(citas_agenda), exit(Pid, kill),         % se cae el sistema
    esperar_nuevo(citas_agenda, Pid),
    timer:sleep(100),
    ok = citas_recordatorios:revisar_ahora(),
    %% El historial visible se vacia con el reinicio, pero las marcas de "entregado"
    %% viven en la cita (persistidas): lo ya enviado NO se repite y lo pendiente SI se envia.
    Tipos = [{P, T} || #{paciente := P, tipo := T} <- citas_recordatorios:listar()],
    ?assertEqual([{<<"Nuevo">>, r48}], Tipos),
    Marcas = [{P, R} || #{paciente := P, recordatorios := R} <- citas_agenda:listar()],
    ?assertMatch(#{r48 := entregado}, proplists:get_value(<<"Ana">>, Marcas)),
    ?assertMatch(#{r48 := entregado}, proplists:get_value(<<"Luis">>, Marcas)),
    ?assertMatch(#{r48 := entregado}, proplists:get_value(<<"Nuevo">>, Marcas)).

prueba_de_caos() ->
    [E1, E2, E3] = citas_sim:caos(),
    ?assertMatch(#{ocurrio := #{agenda_reiniciada := true, recordatorios_reiniciado := true,
                                citas_antes := 20, citas_despues := 20}}, E1),
    ?assertMatch(#{ocurrio := #{recordatorios_reiniciado := true, agenda_intacta := true}}, E2),
    ?assertMatch(#{ocurrio := #{sin_traslapes := true, ids_unicos := true}}, E3).

esperar_nuevo(Nombre, Viejo) -> esperar_nuevo(Nombre, Viejo, 100).
esperar_nuevo(_, _, 0) -> error(no_reinicio);
esperar_nuevo(Nombre, Viejo, N) ->
    case whereis(Nombre) of
        Pid when is_pid(Pid), Pid =/= Viejo -> ok;
        _ -> timer:sleep(20), esperar_nuevo(Nombre, Viejo, N - 1)
    end.
