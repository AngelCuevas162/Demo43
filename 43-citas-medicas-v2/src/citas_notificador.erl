%%% Canal de entrega SIMULADO. En un sistema real aqui iria SMS, WhatsApp o
%%% correo. La probabilidad de fallo es configurable para inyectar fallas.
-module(citas_notificador).
-export([enviar/1]).

enviar(Mensaje) ->
    ProbFallo = application:get_env(citas_medicas, prob_fallo_entrega, 0.0),
    case rand:uniform() < ProbFallo of
        true  -> {error, canal_no_disponible};
        false -> logger:notice("RECORDATORIO ENVIADO: ~ts", [Mensaje]), ok
    end.
