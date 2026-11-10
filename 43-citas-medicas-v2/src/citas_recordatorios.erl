%%% gen_server que cada cierto tiempo revisa la agenda y envia recordatorios a
%%% 48 h y 2 h antes de cada cita.
%%%  - Si la entrega falla se reintenta en la siguiente revision (hasta N veces);
%%%    pasado el maximo se marca "fallido" (y el de 2 h sirve de segunda chance).
%%%  - Lo ya entregado queda escrito en la cita (persistente), asi que tras un
%%%    reinicio no se repite ni se pierde ningun recordatorio pendiente.
-module(citas_recordatorios).
-behaviour(gen_server).

-export([start_link/0, listar/0, revisar_ahora/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(MAX_HISTORIAL, 500).

-record(state, {intervalo_ms   :: pos_integer(),
                ventanas       :: #{r48 := integer(), r2 := integer()},
                max_intentos   :: pos_integer(),
                intentos = #{} :: map(),
                historial = [] :: [map()]}).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Historial de recordatorios (mas recientes primero).
listar()         -> gen_server:call(?MODULE, listar).
%% Fuerza una revision inmediata (pruebas y demos).
revisar_ahora()  -> gen_server:call(?MODULE, revisar).

init([]) ->
    Intervalo = application:get_env(citas_medicas, intervalo_ms, 30000),
    V48 = application:get_env(citas_medicas, ventana_r48_seg, 48 * 3600),
    V2  = application:get_env(citas_medicas, ventana_r2_seg, 2 * 3600),
    Max = application:get_env(citas_medicas, max_intentos, 3),
    programar(Intervalo),
    {ok, #state{intervalo_ms = Intervalo, ventanas = #{r48 => V48, r2 => V2},
                max_intentos = Max}}.

handle_call(listar, _De, #state{historial = H} = S) -> {reply, H, S};
handle_call(revisar, _De, S)                        -> {reply, ok, revisar(S)}.

handle_cast(_Msg, S) -> {noreply, S}.

handle_info(revisar, #state{intervalo_ms = Intervalo} = S) ->
    programar(Intervalo),
    {noreply, revisar(S)};
handle_info(_Otro, S) -> {noreply, S}.

programar(Ms) -> erlang:send_after(Ms, self(), revisar).

revisar(#state{ventanas = Ventanas} = S) ->
    Ahora = erlang:system_time(second),
    Pendientes = try citas_agenda:pendientes_recordatorio(Ahora, Ventanas)
                 catch exit:_ -> []      % la agenda se esta reiniciando
                 end,
    lists:foldl(fun({Cita, Tipo}, Acc) -> procesar(Cita, Tipo, Ahora, Acc) end, S, Pendientes).

procesar(#{id := Id} = Cita, Tipo, Ahora, #state{intentos = Int, max_intentos = Max} = S) ->
    N = maps:get({Id, Tipo}, Int, 0) + 1,
    Base = #{cita_id => Id, tipo => Tipo, generado => Ahora,
             paciente => maps:get(paciente, Cita),
             medico => citas_catalogo:nombre_medico(maps:get(medico, Cita)),
             inicio => maps:get(inicio, Cita), intentos => N,
             mensaje => mensaje(Cita, Tipo)},
    case citas_notificador:enviar(maps:get(mensaje, Base)) of
        ok ->
            citas_agenda:marcar_recordatorio(Id, Tipo, entregado),
            registrar(Base#{estado => entregado}, S#state{intentos = maps:remove({Id, Tipo}, Int)});
        {error, _} when N >= Max ->
            citas_agenda:marcar_recordatorio(Id, Tipo, fallido),
            registrar(Base#{estado => fallido}, S#state{intentos = maps:remove({Id, Tipo}, Int)});
        {error, _} ->
            registrar(Base#{estado => reintentando}, S#state{intentos = Int#{{Id, Tipo} => N}})
    end.

registrar(#{cita_id := Id, tipo := Tipo} = Entrada, #state{historial = H} = S) ->
    Resto = [E || #{cita_id := I, tipo := T} = E <- H, {I, T} =/= {Id, Tipo}],
    S#state{historial = lists:sublist([Entrada | Resto], ?MAX_HISTORIAL)}.

mensaje(#{paciente := P, medico := M, inicio := I}, Tipo) ->
    Hora = calendar:system_time_to_rfc3339(I, [{offset, "Z"}]),
    Cuando = case Tipo of r48 -> "48 horas"; r2 -> "2 horas" end,
    Texto = io_lib:format("~ts: tu cita con ~ts es en ~s (~s UTC). Responde para confirmar o cancelar.",
                          [unicode:characters_to_list(P),
                           unicode:characters_to_list(citas_catalogo:nombre_medico(M)),
                           Cuando, Hora]),
    unicode:characters_to_binary(Texto).
