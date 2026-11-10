%%% Catalogo fijo de recursos: 10 medicos y 4 consultorios (escenario del enunciado).
-module(citas_catalogo).
-export([medicos/0, consultorios/0, existe_medico/1, existe_consultorio/1, nombre_medico/1]).

medicos() ->
    [medico(<<"m01">>, <<"Dra. Ana Torres"/utf8>>,      <<"Medicina general"/utf8>>),
     medico(<<"m02">>, <<"Dr. Luis Ramírez"/utf8>>,     <<"Pediatría"/utf8>>),
     medico(<<"m03">>, <<"Dra. Carmen Ortega"/utf8>>,   <<"Ginecología"/utf8>>),
     medico(<<"m04">>, <<"Dr. Jorge Medina"/utf8>>,     <<"Cardiología"/utf8>>),
     medico(<<"m05">>, <<"Dra. Sofía Navarro"/utf8>>,   <<"Dermatología"/utf8>>),
     medico(<<"m06">>, <<"Dr. Pablo Herrera"/utf8>>,    <<"Traumatología"/utf8>>),
     medico(<<"m07">>, <<"Dra. Elena Ruiz"/utf8>>,      <<"Oftalmología"/utf8>>),
     medico(<<"m08">>, <<"Dr. Marcos Salazar"/utf8>>,   <<"Neurología"/utf8>>),
     medico(<<"m09">>, <<"Dra. Lucía Vega"/utf8>>,      <<"Medicina interna"/utf8>>),
     medico(<<"m10">>, <<"Dr. Andrés Castillo"/utf8>>,  <<"Otorrinolaringología"/utf8>>)].

medico(Id, Nombre, Especialidad) ->
    #{id => Id, nombre => Nombre, especialidad => Especialidad}.

consultorios() -> [<<"C1">>, <<"C2">>, <<"C3">>, <<"C4">>].

existe_medico(Id) -> lists:any(fun(#{id := I}) -> I =:= Id end, medicos()).
existe_consultorio(Id) -> lists:member(Id, consultorios()).

nombre_medico(Id) ->
    case [N || #{id := I, nombre := N} <- medicos(), I =:= Id] of
        [N | _] -> N;
        []      -> Id
    end.
