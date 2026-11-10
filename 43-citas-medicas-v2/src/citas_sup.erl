%%% Supervisor raiz. rest_for_one: citas_recordatorios depende de citas_agenda.
%%% Si la agenda muere, ambos se reinician (la agenda recarga su estado del
%%% disco); si solo muere recordatorios, la agenda sigue intacta.
%%% La intensidad es alta (20 en 10 s) para tolerar las pruebas de caos en vivo.
-module(citas_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => rest_for_one, intensity => 20, period => 10},
    Hijos = [
        #{id => citas_agenda, start => {citas_agenda, start_link, []},
          restart => permanent, shutdown => 5000, type => worker},
        #{id => citas_recordatorios, start => {citas_recordatorios, start_link, []},
          restart => permanent, shutdown => 5000, type => worker}
    ],
    {ok, {SupFlags, Hijos}}.
