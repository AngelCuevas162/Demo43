%%% Logica PURA de la agenda (sin procesos): facil de probar.
%%%
%%% Representacion del tiempo: una cita ocupa el intervalo semiabierto
%%% [inicio, fin) en segundos UTC (epoch). Dos citas se traslapan si y solo si
%%%     inicio1 < fin2  Y  inicio2 < fin1
%%% Como se guarda UTC, el cambio de horario de verano no altera los traslapes;
%%% solo cambia como se MUESTRA la hora local (lo convierte el navegador).
-module(citas_reglas).
-export([activa/1, ocupa/1, fin/1, se_traslapan/2, validar/4, sin_traslapes/1]).

%% Citas que bloquean horario hacia adelante.
activa(#{estado := E}) -> E =:= programada orelse E =:= confirmada.

%% Citas que ocuparon un horario (incluye las ya atendidas o no-show).
ocupa(#{estado := E}) ->
    lists:member(E, [programada, confirmada, atendida, no_show]).

fin(#{inicio := I, duracion_min := D}) -> I + D * 60.

se_traslapan(A, B) ->
    maps:get(inicio, A) < fin(B) andalso maps:get(inicio, B) < fin(A).

%% Valida una solicitud. Devuelve {ok, Consultorio} | {error, Razon}.
validar(#{paciente := P, medico := M, inicio := I, duracion_min := D} = Datos,
        Ahora, Activas, Bajas)
  when is_binary(P), is_binary(M), is_integer(I), is_integer(D) ->
    Motivo = maps:get(motivo, Datos, <<>>),
    Pedido = maps:get(consultorio, Datos, auto),
    if
        P =:= <<>> orelse M =:= <<>>               -> {error, datos_incompletos};
        not is_binary(Motivo)                      -> {error, datos_invalidos};
        not (Pedido =:= auto orelse is_binary(Pedido)) -> {error, datos_invalidos};
        D < 5 orelse D > 240                       -> {error, duracion_invalida};
        I =< Ahora                                 -> {error, en_el_pasado};
        true -> validar_recursos(P, M, I, D, Pedido, Activas, Bajas)
    end;
validar(_, _, _, _) ->
    {error, datos_invalidos}.

validar_recursos(P, M, I, D, Pedido, Activas, Bajas) ->
    Cand = #{inicio => I, duracion_min => D},
    Choque = [A || A <- Activas, se_traslapan(Cand, A)],
    case citas_catalogo:existe_medico(M) of
        false -> {error, medico_desconocido};
        true ->
            case lists:member(M, Bajas) of
                true -> {error, medico_de_baja};
                false ->
                    case {[x || #{medico := X} <- Choque, X =:= M],
                          [x || #{paciente := Y} <- Choque, Y =:= P]} of
                        {[_ | _], _} -> {error, traslape_medico};
                        {_, [_ | _]} -> {error, traslape_paciente};
                        _            -> elegir_consultorio(Pedido, Choque)
                    end
            end
    end.

elegir_consultorio(auto, Choque) ->
    Ocupados = [C || #{consultorio := C} <- Choque],
    case [C || C <- citas_catalogo:consultorios(), not lists:member(C, Ocupados)] of
        []      -> {error, sin_consultorio};
        [C | _] -> {ok, C}
    end;
elegir_consultorio(Pedido, Choque) ->
    case citas_catalogo:existe_consultorio(Pedido) of
        false -> {error, consultorio_desconocido};
        true  ->
            case [x || #{consultorio := C} <- Choque, C =:= Pedido] of
                [] -> {ok, Pedido};
                _  -> {error, traslape_consultorio}
            end
    end.

%% Invariante global: ningun par de citas comparte medico, paciente o
%% consultorio en el mismo intervalo.
sin_traslapes(Citas) ->
    Pares = [{A, B} || [A | Resto] <- colas(Citas), B <- Resto],
    not lists:any(
          fun({A, B}) ->
                  se_traslapan(A, B) andalso
                      (maps:get(medico, A) =:= maps:get(medico, B) orelse
                       maps:get(paciente, A) =:= maps:get(paciente, B) orelse
                       maps:get(consultorio, A) =:= maps:get(consultorio, B))
          end, Pares).

colas([])            -> [];
colas([_ | T] = Lista) -> [Lista | colas(T)].
