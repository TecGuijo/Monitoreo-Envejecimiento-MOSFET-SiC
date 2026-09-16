clc;
clear;
close all;

% =========================================================
%  DATASET DE PRUEBA KNN - MUESTRAS ALEATORIAS
%  CON CLASIFICACION POR PARAMETRO
%
%  Entradas:
%  1) RESUMEN.csv
%  2) Carpeta con TDUT_TJ_RDSON_PARTE_*.csv
%  3) Archivo VTH_CICLO_SIMPLE.csv
%
%  Salida:
%  KNN_PRUEBA_N.csv
%
%  Columnas:
%  valorRDSon, clasificacionRDSon,
%  valorVth,   clasificacionVth,
%  valorTj,    clasificacionTj
%
%  Clasificacion:
%  1 = Sano / estabilidad termica
%  2 = Degradacion inicial / creacion de grietas
%  3 = Degradacion severa / falla
%  4 = Postfalla
%
%  Ajusta aqui el numero de pruebas deseadas:
% =========================================================

N_muestras = 200;   % <<< CAMBIA AQUI EL NUMERO DE MUESTRAS DE PRUEBA

patronArchivosRDS_TJ = 'TDUT_TJ_RDSON_PARTE_*.csv';
nombreSalidaCSV      = sprintf('DATA_PRUEBA_VAL_%d.csv', N_muestras);

rng('shuffle');

% =========================================================
%  1) SELECCIONAR RESUMEN.csv
% =========================================================
[fileResumen, pathResumen] = uigetfile( ...
    {'*.csv;*.xlsx;*.xls', 'Archivo de etapas (*.csv, *.xlsx, *.xls)'}, ...
    'Selecciona el archivo RESUMEN.csv');

if isequal(fileResumen, 0)
    error('No seleccionaste el archivo RESUMEN.csv.');
end

rutaResumen = fullfile(pathResumen, fileResumen);

fprintf('\nLeyendo archivo RESUMEN:\n%s\n', rutaResumen);
drawnow;

T_resumen = leer_tabla_robusta(rutaResumen);
T_resumen.Properties.VariableNames = matlab.lang.makeValidName(T_resumen.Properties.VariableNames);

% =========================================================
%  2) SELECCIONAR CARPETA CON TDUT_TJ_RDSON_PARTE_*.csv
% =========================================================
carpetaRDS_TJ = uigetdir(pathResumen, ...
    'Selecciona la carpeta de postprocesamiento con TDUT_TJ_RDSON_PARTE_*.csv');

if isequal(carpetaRDS_TJ, 0)
    error('No seleccionaste la carpeta de RDSon y Tj.');
end

fprintf('\nCarpeta seleccionada:\n%s\n', carpetaRDS_TJ);
drawnow;

archivosRDS_TJ = dir(fullfile(carpetaRDS_TJ, patronArchivosRDS_TJ));

if isempty(archivosRDS_TJ)
    error('No se encontraron archivos con el patron: %s', patronArchivosRDS_TJ);
end

[~, idxOrdArch] = sort({archivosRDS_TJ.name});
archivosRDS_TJ = archivosRDS_TJ(idxOrdArch);

fprintf('\nArchivos encontrados de RDSon/Tj: %d\n', numel(archivosRDS_TJ));
drawnow;

T_datos_cell = cell(numel(archivosRDS_TJ), 1);

for k = 1:numel(archivosRDS_TJ)

    rutaArchivo = fullfile(carpetaRDS_TJ, archivosRDS_TJ(k).name);

    fprintf('Leyendo %s (%d/%d)\n', ...
        archivosRDS_TJ(k).name, k, numel(archivosRDS_TJ));
    drawnow;

    Tk = leer_tabla_robusta(rutaArchivo);
    Tk.Properties.VariableNames = matlab.lang.makeValidName(Tk.Properties.VariableNames);

    T_datos_cell{k} = Tk;
end

fprintf('\nUniendo archivos RDSon/Tj...\n');
drawnow;

T_datos = vertcat(T_datos_cell{:});
clear T_datos_cell;

fprintf('Filas totales RDSon/Tj: %d\n', height(T_datos));
drawnow;

% =========================================================
%  3) SELECCIONAR ARCHIVO VTH_CICLO_SIMPLE.csv
% =========================================================
[fileVth, pathVth] = uigetfile( ...
    {'*.csv;*.xlsx;*.xls', 'Archivo de Vth dinamico (*.csv, *.xlsx, *.xls)'}, ...
    'Selecciona el archivo VTH_CICLO_SIMPLE.csv');

if isequal(fileVth, 0)
    error('No seleccionaste el archivo de Vth dinamico.');
end

rutaVth = fullfile(pathVth, fileVth);

fprintf('\nLeyendo archivo Vth:\n%s\n', rutaVth);
drawnow;

T_vth = leer_tabla_robusta(rutaVth);
T_vth.Properties.VariableNames = matlab.lang.makeValidName(T_vth.Properties.VariableNames);

fprintf('Filas totales Vth: %d\n', height(T_vth));
drawnow;

% =========================================================
%  DETECTAR COLUMNAS DEL RESUMEN
% =========================================================
colsResumen = T_resumen.Properties.VariableNames;

colEtapa = buscar_columna(colsResumen, ...
    {'Etapa', 'etapa', 'Stage', 'stage', 'Estado', 'estado', ...
     'Clasificacion', 'clasificacion', 'Clase', 'clase'});

colTiempoIni = buscar_columna(colsResumen, ...
    {'Tiempo_inicio_s', 'TiempoInicio_s', 'Tiempo_ini_s', ...
     'TiempoInicial_s', 't_ini', 't_inicio', 'inicio_s', ...
     'time_start', 'time_ini'});

colTiempoFin = buscar_columna(colsResumen, ...
    {'Tiempo_fin_s', 'TiempoFin_s', 'Tiempo_final_s', ...
     'TiempoFinal_s', 't_fin', 't_final', 'fin_s', ...
     'time_end', 'time_fin'});

colCicloIni = buscar_columna(colsResumen, ...
    {'Ciclo_inicio', 'CicloInicio', 'Ciclo_ini', ...
     'CicloInicial', 'cycle_start', 'cycle_ini'});

colCicloFin = buscar_columna(colsResumen, ...
    {'Ciclo_fin', 'CicloFin', 'Ciclo_final', ...
     'CicloFinal', 'cycle_end', 'cycle_fin'});

if isempty(colEtapa)
    error('No se encontro la columna Etapa o Clasificacion en RESUMEN.csv.');
end

if isempty(colTiempoIni) || isempty(colTiempoFin)
    error('No se encontraron columnas Tiempo_inicio_s y Tiempo_fin_s.');
end

if isempty(colCicloIni) || isempty(colCicloFin)
    error('No se encontraron columnas Ciclo_inicio y Ciclo_fin.');
end

% =========================================================
%  DETECTAR COLUMNAS DE TDUT_TJ_RDSON
% =========================================================
colsDatos = T_datos.Properties.VariableNames;

colTiempoDatos = buscar_columna(colsDatos, ...
    {'Tiempo_s', 'Tiempo', 'Time_s', 'Time', 't_s', 't', ...
     'TiempoGlobal_s', 'Tiempo_Global_s'});

colRDSon = buscar_columna(colsDatos, ...
    {'RDSon_Ohm', 'RDSon', 'Rdson', 'RDS_on', ...
     'RDS_on_Ohm', 'RDSon_ohms', 'RDS'});

colTj = buscar_columna(colsDatos, ...
    {'Tj_C', 'Tj', 'Tj_calc', 'Tjunction', ...
     'Temp_juncion', 'Temperatura_juncion'});

colMascaraRDSon = buscar_columna(colsDatos, ...
    {'MascaraRDSon', 'Mascara_RDSon', 'MaskRDSon', ...
     'Mask_RDSon', 'RDSonMask'});

if isempty(colTiempoDatos)
    error('No se encontro columna de tiempo en TDUT_TJ_RDSON.');
end

if isempty(colRDSon)
    error('No se encontro columna RDSon.');
end

if isempty(colTj)
    error('No se encontro columna Tj.');
end

% =========================================================
%  DETECTAR COLUMNAS DE Vth
% =========================================================
colsVth = T_vth.Properties.VariableNames;

colCicloVth = buscar_columna(colsVth, ...
    {'Ciclo', 'Cycle', 'N_ciclo', 'NCiclo', 'NumeroCiclo'});

colVth = buscar_columna(colsVth, ...
    {'Vth_dinamico_V', 'VthDinamico', 'Vth_Dinamico', ...
     'Vth_V', 'Vth', 'VTH', 'Vthreshold', ...
     'Threshold', 'Voltaje_umbral'});

colEstadoVth = buscar_columna(colsVth, ...
    {'Estado', 'estado', 'Status', 'status'});

if isempty(colCicloVth)
    error('No se encontro columna Ciclo en el archivo de Vth.');
end

if isempty(colVth)
    error('No se encontro columna Vth_dinamico_V en el archivo de Vth.');
end

% =========================================================
%  EXTRAER MAPA CICLO -> TIEMPO -> CLASIFICACION
% =========================================================
fprintf('\nConstruyendo mapa ciclo-tiempo-clasificacion desde RESUMEN...\n');
drawnow;

etapaRaw = T_resumen.(colEtapa);
clasificacionResumen = convertir_etapas_a_numero(etapaRaw);

tIni = limpiar_vector_numerico(T_resumen.(colTiempoIni));
tFin = limpiar_vector_numerico(T_resumen.(colTiempoFin));

cIni = limpiar_vector_numerico(T_resumen.(colCicloIni));
cFin = limpiar_vector_numerico(T_resumen.(colCicloFin));

maskResumen = isfinite(clasificacionResumen) & ...
              isfinite(tIni) & isfinite(tFin) & ...
              isfinite(cIni) & isfinite(cFin);

clasificacionResumen = clasificacionResumen(maskResumen);
tIni                 = tIni(maskResumen);
tFin                 = tFin(maskResumen);
cIni                 = cIni(maskResumen);
cFin                 = cFin(maskResumen);

for k = 1:numel(tIni)

    if tIni(k) > tFin(k)
        aux = tIni(k);
        tIni(k) = tFin(k);
        tFin(k) = aux;
    end

    if cIni(k) > cFin(k)
        aux = cIni(k);
        cIni(k) = cFin(k);
        cFin(k) = aux;
    end
end

fprintf('Rangos validos para muestreo:\n');

for k = 1:numel(tIni)
    fprintf('  Clasificacion %.0f | Ciclos %.0f a %.0f | Tiempo %.3f s a %.3f s\n', ...
        clasificacionResumen(k), cIni(k), cFin(k), tIni(k), tFin(k));
end

drawnow;

% =========================================================
%  EXTRAER Y LIMPIAR RDSon / Tj
% =========================================================
fprintf('\nExtrayendo RDSon y Tj...\n');
drawnow;

tDatos = limpiar_vector_numerico(T_datos.(colTiempoDatos));
rdson  = limpiar_vector_numerico(T_datos.(colRDSon));
tj     = limpiar_vector_numerico(T_datos.(colTj));

rdson = rellenar_nan_con_vecinos(rdson);
tj    = rellenar_nan_con_vecinos(tj);

if ~isempty(colMascaraRDSon)
    mascaraRDSon = limpiar_vector_numerico(T_datos.(colMascaraRDSon));
    maskRDSonBase = isfinite(tDatos) & isfinite(rdson) & mascaraRDSon == 1;
else
    maskRDSonBase = isfinite(tDatos) & isfinite(rdson);
end

maskTjBase = isfinite(tDatos) & isfinite(tj);

tRDSon = tDatos(maskRDSonBase);
rdson  = rdson(maskRDSonBase);

tTj = tDatos(maskTjBase);
tj  = tj(maskTjBase);

clear T_datos tDatos;

[tRDSon, idxOrdR] = sort(tRDSon);
rdson = rdson(idxOrdR);

[tRDSon, idxUniR] = unique(tRDSon, 'stable');
rdson = rdson(idxUniR);

[tTj, idxOrdT] = sort(tTj);
tj = tj(idxOrdT);

[tTj, idxUniT] = unique(tTj, 'stable');
tj = tj(idxUniT);

rdson = rellenar_nan_con_vecinos(rdson);
tj    = rellenar_nan_con_vecinos(tj);

fprintf('RDSon validos: %d\n', numel(rdson));
fprintf('Tj validos:    %d\n', numel(tj));
drawnow;

% =========================================================
%  EXTRAER Y LIMPIAR Vth
% =========================================================
fprintf('\nExtrayendo Vth por ciclo...\n');
drawnow;

cicloVth = limpiar_vector_numerico(T_vth.(colCicloVth));
vth      = limpiar_vector_numerico(T_vth.(colVth));

if ~isempty(colEstadoVth)
    estadoVth = lower(string(T_vth.(colEstadoVth)));
else
    estadoVth = strings(size(vth));
end

vth = rellenar_nan_con_vecinos(vth);

maskVth = isfinite(cicloVth) & isfinite(vth);

cicloVth  = cicloVth(maskVth);
vth       = vth(maskVth);
estadoVth = estadoVth(maskVth);

[cicloVth, idxOrdV] = sort(cicloVth);
vth       = vth(idxOrdV);
estadoVth = estadoVth(idxOrdV);

[cicloVth, vth] = compactar_vth_por_ciclo(cicloVth, vth, estadoVth);

vth = rellenar_nan_con_vecinos(vth);

clear T_vth;

fprintf('Vth validos por ciclo: %d\n', numel(vth));
drawnow;

% =========================================================
%  CICLOS CANDIDATOS
% =========================================================
fprintf('\nBuscando ciclos candidatos...\n');
drawnow;

cicloMinResumen = ceil(min(cIni));
cicloMaxResumen = floor(max(cFin));

ciclosResumen = (cicloMinResumen:cicloMaxResumen).';

ciclosCandidatos = intersect(ciclosResumen, cicloVth);

maskCandidatosValidos = false(size(ciclosCandidatos));

for k = 1:numel(ciclosCandidatos)

    cicloActual = ciclosCandidatos(k);

    [t0, t1, clasifTmp, okVentana] = obtener_ventana_tiempo_ciclo( ...
        cicloActual, cIni, cFin, tIni, tFin, clasificacionResumen);

    if ~okVentana || ~isfinite(clasifTmp)
        continue;
    end

    hayRDSon = any(tRDSon >= t0 & tRDSon <= t1);
    hayTj    = any(tTj    >= t0 & tTj    <= t1);

    maskCandidatosValidos(k) = hayRDSon && hayTj;
end

ciclosCandidatos = ciclosCandidatos(maskCandidatosValidos);

fprintf('Ciclos candidatos validos: %d\n', numel(ciclosCandidatos));
drawnow;

if numel(ciclosCandidatos) < N_muestras
    error('Solo hay %d ciclos validos, pero se pidieron %d muestras.', ...
        numel(ciclosCandidatos), N_muestras);
end

% =========================================================
%  SELECCION ALEATORIA
% =========================================================
idxRandom = randperm(numel(ciclosCandidatos), N_muestras);
ciclosSeleccionados = ciclosCandidatos(idxRandom);
ciclosSeleccionados = ciclosSeleccionados(:);

fprintf('\nCiclos seleccionados aleatoriamente: %d\n', numel(ciclosSeleccionados));
drawnow;

% =========================================================
%  EXTRAER RDSon, Vth, Tj Y CLASIFICACION POR CICLO
% =========================================================
valorRDSon = zeros(N_muestras, 1);
valorVth   = zeros(N_muestras, 1);
valorTj    = zeros(N_muestras, 1);

clasificacionRDSon = zeros(N_muestras, 1);
clasificacionVth   = zeros(N_muestras, 1);
clasificacionTj    = zeros(N_muestras, 1);

fprintf('\nGenerando dataset de prueba con clasificacion por parametro...\n');
drawnow;

for i = 1:N_muestras

    cicloActual = ciclosSeleccionados(i);

    [t0, t1, clasificacionActual, okVentana] = obtener_ventana_tiempo_ciclo( ...
        cicloActual, cIni, cFin, tIni, tFin, clasificacionResumen);

    if ~okVentana
        error('No se pudo calcular ventana de tiempo para el ciclo %.0f.', cicloActual);
    end

    maskR = tRDSon >= t0 & tRDSon <= t1;
    maskT = tTj    >= t0 & tTj    <= t1;

    rdsonCiclo = rdson(maskR);
    tjCiclo    = tj(maskT);

    if isempty(rdsonCiclo)
        valorRDSon(i) = interp1(tRDSon, rdson, (t0+t1)/2, 'linear', 'extrap');
    else
        valorRDSon(i) = median(rdsonCiclo, 'omitnan');
    end

    if isempty(tjCiclo)
        valorTj(i) = interp1(tTj, tj, (t0+t1)/2, 'linear', 'extrap');
    else
        valorTj(i) = median(tjCiclo, 'omitnan');
    end

    valorVth(i) = interp1(cicloVth, vth, cicloActual, 'nearest', 'extrap');

    % La clasificacion pertenece al ciclo completo.
    % Se copia para cada parametro para mantener el formato del dataset train.
    clasificacionRDSon(i) = clasificacionActual;
    clasificacionVth(i)   = clasificacionActual;
    clasificacionTj(i)    = clasificacionActual;

    if mod(i, 25) == 0 || i == N_muestras
        fprintf('  Muestras generadas: %d/%d\n', i, N_muestras);
        drawnow;
    end
end

valorRDSon = rellenar_nan_con_vecinos(valorRDSon);
valorVth   = rellenar_nan_con_vecinos(valorVth);
valorTj    = rellenar_nan_con_vecinos(valorTj);

% =========================================================
%  VERIFICACION FINAL
% =========================================================
nNanR  = sum(isnan(valorRDSon));
nNanV  = sum(isnan(valorVth));
nNanT  = sum(isnan(valorTj));
nNanCR = sum(isnan(clasificacionRDSon));
nNanCV = sum(isnan(clasificacionVth));
nNanCT = sum(isnan(clasificacionTj));

fprintf('\nNaN finales:\n');
fprintf('RDSon:               %d\n', nNanR);
fprintf('Vth:                 %d\n', nNanV);
fprintf('Tj:                  %d\n', nNanT);
fprintf('Clasificacion RDSon: %d\n', nNanCR);
fprintf('Clasificacion Vth:   %d\n', nNanCV);
fprintf('Clasificacion Tj:    %d\n', nNanCT);

if nNanR > 0 || nNanV > 0 || nNanT > 0 || ...
   nNanCR > 0 || nNanCV > 0 || nNanCT > 0
    warning('Aun quedaron NaN en el dataset final.');
end

% =========================================================
%  TABLA FINAL PARA PRUEBA
%  FORMATO COMPATIBLE CON EL CODIGO DE PYTHON
% =========================================================
datasetPrueba = table( ...
    valorRDSon, ...
    clasificacionRDSon, ...
    valorVth, ...
    clasificacionVth, ...
    valorTj, ...
    clasificacionTj);

% =========================================================
%  GUARDAR SOLO CSV PRINCIPAL
% =========================================================
rutaSalidaCSV = fullfile(carpetaRDS_TJ, nombreSalidaCSV);

fprintf('\nGuardando CSV final de prueba...\n');
drawnow;

writetable(datasetPrueba, rutaSalidaCSV);

% =========================================================
%  MENSAJE FINAL
% =========================================================
fprintf('\n=============================================\n');
fprintf('DATASET DE PRUEBA GENERADO CORRECTAMENTE\n');
fprintf('=============================================\n');
fprintf('Filas totales: %d\n', height(datasetPrueba));
fprintf('Muestras aleatorias: %d\n', N_muestras);
fprintf('\nCSV principal guardado en:\n%s\n', rutaSalidaCSV);
fprintf('=============================================\n');

% =========================================================
%  FUNCIONES LOCALES
% =========================================================

function T = leer_tabla_robusta(ruta)

    [~, ~, ext] = fileparts(ruta);
    ext = lower(ext);

    switch ext

        case '.csv'

            try
                opts = detectImportOptions(ruta, 'Delimiter', ',');
                opts.VariableNamingRule = 'preserve';
                T = readtable(ruta, opts);

                if width(T) <= 1
                    opts = detectImportOptions(ruta, 'Delimiter', ';');
                    opts.VariableNamingRule = 'preserve';
                    T = readtable(ruta, opts);
                end

            catch
                opts = detectImportOptions(ruta, 'Delimiter', ';');
                opts.VariableNamingRule = 'preserve';
                T = readtable(ruta, opts);
            end

        case {'.xlsx', '.xls'}

            opts = detectImportOptions(ruta);
            opts.VariableNamingRule = 'preserve';
            T = readtable(ruta, opts);

        otherwise
            error('Formato no soportado: %s', ext);
    end
end

function col = buscar_columna(listaColumnas, candidatos)

    col = '';

    listaLower = lower(string(listaColumnas));
    listaLower = limpiar_nombre_columna(listaLower);

    candidatosLower = lower(string(candidatos));
    candidatosLower = limpiar_nombre_columna(candidatosLower);

    for i = 1:numel(candidatosLower)
        idx = find(listaLower == candidatosLower(i), 1, 'first');
        if ~isempty(idx)
            col = listaColumnas{idx};
            return;
        end
    end

    for i = 1:numel(candidatosLower)
        idx = find(contains(listaLower, candidatosLower(i)), 1, 'first');
        if ~isempty(idx)
            col = listaColumnas{idx};
            return;
        end
    end
end

function nombres = limpiar_nombre_columna(nombres)

    nombres = string(nombres);

    nombres = erase(nombres, "_");
    nombres = erase(nombres, " ");
    nombres = erase(nombres, "-");
    nombres = erase(nombres, "(");
    nombres = erase(nombres, ")");
    nombres = erase(nombres, "[");
    nombres = erase(nombres, "]");
    nombres = erase(nombres, "/");
    nombres = erase(nombres, "\");
    nombres = erase(nombres, ".");
    nombres = erase(nombres, "°");
end

function x = limpiar_vector_numerico(xRaw)

    if isnumeric(xRaw)
        x = double(xRaw);
        return;
    end

    if iscell(xRaw)
        xRaw = string(xRaw);
    end

    if iscategorical(xRaw)
        xRaw = string(xRaw);
    end

    if isdatetime(xRaw)
        x = seconds(xRaw - xRaw(1));
        return;
    end

    if isduration(xRaw)
        x = seconds(xRaw);
        return;
    end

    if isstring(xRaw) || ischar(xRaw)

        xStr = string(xRaw);

        xStr = strrep(xStr, ',', '.');

        xStr = erase(xStr, 'Ohm');
        xStr = erase(xStr, 'ohm');
        xStr = erase(xStr, 'OHM');

        xStr = erase(xStr, 'V');
        xStr = erase(xStr, 'v');

        xStr = erase(xStr, 'C');
        xStr = erase(xStr, '°');

        xStr = erase(xStr, 's');
        xStr = erase(xStr, 'A');
        xStr = erase(xStr, 'a');

        x = str2double(xStr);
        return;
    end

    try
        x = double(xRaw);
    catch
        x = nan(size(xRaw));
    end
end

function etapasNum = convertir_etapas_a_numero(etapaRaw)

    if isnumeric(etapaRaw)
        etapasNum = double(etapaRaw);
        return;
    end

    if iscell(etapaRaw)
        etapaRaw = string(etapaRaw);
    end

    if iscategorical(etapaRaw)
        etapaRaw = string(etapaRaw);
    end

    etapaStr = lower(string(etapaRaw));

    etapasNum = nan(size(etapaStr));

    for k = 1:numel(etapaStr)

        e = etapaStr(k);

        eClean = erase(e, " ");
        eClean = erase(eClean, "_");
        eClean = erase(eClean, "-");

        eClean = strrep(eClean, "á", "a");
        eClean = strrep(eClean, "é", "e");
        eClean = strrep(eClean, "í", "i");
        eClean = strrep(eClean, "ó", "o");
        eClean = strrep(eClean, "ú", "u");

        if contains(eClean, "transitorio")
            etapasNum(k) = NaN;

        elseif contains(eClean, "postfalla") || ...
               contains(eClean, "postfallo") || ...
               contains(eClean, "post") || ...
               contains(eClean, "4")

            etapasNum(k) = 4;

        elseif contains(eClean, "falla") || ...
               contains(eClean, "fallo") || ...
               contains(eClean, "3")

            etapasNum(k) = 3;

        elseif contains(eClean, "creaciongrietas") || ...
               contains(eClean, "grieta") || ...
               contains(eClean, "grietas") || ...
               contains(eClean, "degradacion") || ...
               contains(eClean, "2")

            etapasNum(k) = 2;

        elseif contains(eClean, "estabilidadtermica") || ...
               contains(eClean, "estabilidad") || ...
               contains(eClean, "estable") || ...
               contains(eClean, "termica") || ...
               contains(eClean, "normal") || ...
               contains(eClean, "sano") || ...
               contains(eClean, "1")

            etapasNum(k) = 1;

        else
            etapasNum(k) = NaN;
        end
    end
end

function x = rellenar_nan_con_vecinos(x)

    x = x(:);

    if isempty(x)
        return;
    end

    if all(isnan(x))
        return;
    end

    try
        x = fillmissing(x, 'linear', 'EndValues', 'nearest');
        x = fillmissing(x, 'nearest');
    catch
        idxVal = find(isfinite(x));

        if isempty(idxVal)
            return;
        end

        idxNan = find(~isfinite(x));

        for k = 1:numel(idxNan)
            [~, pos] = min(abs(idxVal - idxNan(k)));
            x(idxNan(k)) = x(idxVal(pos));
        end
    end

    if any(isnan(x))
        idxVal = find(isfinite(x));

        if ~isempty(idxVal)
            idxNan = find(~isfinite(x));

            for k = 1:numel(idxNan)
                [~, pos] = min(abs(idxVal - idxNan(k)));
                x(idxNan(k)) = x(idxVal(pos));
            end
        end
    end
end

function [cU, vU] = compactar_vth_por_ciclo(ciclo, vth, estado)

    ciclo  = ciclo(:);
    vth    = vth(:);
    estado = string(estado(:));

    mask = isfinite(ciclo);

    ciclo  = ciclo(mask);
    vth    = vth(mask);
    estado = estado(mask);

    [cU, ~, ic] = unique(ciclo, 'stable');

    vU = nan(size(cU));

    for k = 1:numel(cU)

        vals = vth(ic == k);
        est  = lower(estado(ic == k));

        maskOK = contains(est, "ok") & isfinite(vals);

        if any(maskOK)
            valsOK = vals(maskOK);
            vU(k) = median(valsOK);
        else
            valsValidos = vals(isfinite(vals));

            if ~isempty(valsValidos)
                vU(k) = median(valsValidos);
            else
                vU(k) = NaN;
            end
        end
    end

    vU = rellenar_nan_con_vecinos(vU);
end

function [t0, t1, clasificacionActual, ok] = obtener_ventana_tiempo_ciclo( ...
    cicloActual, cIni, cFin, tIni, tFin, clasificacionResumen)

    ok = false;
    t0 = NaN;
    t1 = NaN;
    clasificacionActual = NaN;

    idx = find(cicloActual >= cIni & cicloActual <= cFin, 1, 'first');

    if isempty(idx)
        return;
    end

    nCiclos = cFin(idx) - cIni(idx) + 1;

    if nCiclos <= 0
        return;
    end

    dtCiclo = (tFin(idx) - tIni(idx)) / nCiclos;

    t0 = tIni(idx) + (cicloActual - cIni(idx)) * dtCiclo;
    t1 = t0 + dtCiclo;

    clasificacionActual = clasificacionResumen(idx);

    if ~isfinite(t0) || ~isfinite(t1) || t1 <= t0 || ~isfinite(clasificacionActual)
        ok = false;
    else
        ok = true;
    end
end