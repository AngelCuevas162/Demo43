%%% Punto de entrada de la aplicacion OTP: arranca el arbol de supervision
%%% y el servidor HTTP (cowboy).
-module(citas_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_Tipo, _Args) ->
    {ok, Sup} = citas_sup:start_link(),
    Puerto = application:get_env(citas_medicas, puerto, 8081),
    Dispatch = cowboy_router:compile([
        {'_', [
            %% pantallas
            {"/",         cowboy_static, {priv_file, citas_medicas, "index.html"}},
            {"/medicos",  cowboy_static, {priv_file, citas_medicas, "medicos.html"}},
            {"/panel",    cowboy_static, {priv_file, citas_medicas, "panel.html"}},
            %% API
            {"/api/catalogo",              citas_http, catalogo},
            {"/api/citas",                 citas_http, citas},
            {"/api/citas/:id",             citas_http, cancelar},
            {"/api/citas/:id/confirmar",   citas_http, confirmar},
            {"/api/recordatorios",         citas_http, recordatorios},
            {"/api/espera",                citas_http, espera},
            {"/api/medicos/:id/baja",      citas_http, baja},
            {"/api/medicos/:id/alta",      citas_http, alta},
            {"/api/estadisticas",          citas_http, estadisticas},
            {"/api/simulacion",            citas_http, simulacion},
            {"/api/simulacion/caos",       citas_http, caos},
            {"/api/agenda",                citas_http, limpiar}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(citas_listener, [{port, Puerto}],
                                 #{env => #{dispatch => Dispatch}}),
    logger:info("Citas medicas escuchando en el puerto ~p", [Puerto]),
    {ok, Sup}.

stop(_Estado) ->
    ok = cowboy:stop_listener(citas_listener).
