clc;
clear;
close all;

% =========================================================
%  DATASET KNN 4 ETAPAS - CORREGIDO POR CICLO
%  RDSon + Vth dinamico + Tj
%
%  Una fila = un ciclo real del experimento.
%
%  Para cada ciclo:
%  - RDSon = promedio entre segundo 7 y 8 del pulso ON
%  - Tj    = promedio durante todo el ciclo de 30 s
%  - Vth   = Vth dinamico del mismo ciclo
%  - Etapa = etapa correspondiente al mismo ciclo
%
%  CASO ESPECIAL:
%  Etapa 4 = transistor abierto / sin conmutacion.
%  Si RDSon o Vth no existen, se codifican como 0
%  y el ciclo se considera valido.
%
%  Salida principal:
%  DATA_TRAIN.csv
%
%  Columnas:
%  valorRDSon, clasificacionRDSon,
%  valorVth,   clasificacionVth,
%  valorTj,    clasificacionTj
% =========================================================

% =========================================================
%  CONFIGURACION GENERAL
% =========================================================
N_por_etapa = 210;
numEtapas   = 4;

patronArchivosRDS_TJ = 'TDUT_TJ_RDSON_PARTE_*.csv';

nombreSalidaPorCiclo      = 'DATA_POR_CICLO.csv';
nombreSalidaTrain         = 'DATA_TRAIN.csv';
nombreSalidaTrainConCiclo = 'DATA_TRAIN_CON_CICLO.csv';

% =========================================================
%  CONFIGURACION DEL PERFIL PCmin
% =========================================================
Ton_s      = 15;
Toff_s     = 15;
Tperiodo_s = Ton_s + Toff_s;

% Si tu archivo Vth empieza en ciclo 1, dejar en 1.
% Si tus ciclos empiezan en 0, cambiar a 0.
cicloReferencia = 1;

% Normalmente debe ser 0.
tiempoOffset_s = 0;

% Ventana para RDSon dentro del pulso ON.
ventanaRDS_ini_s = 7;
ventanaRDS_fin_s = 8;

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

fprintf('\nLeyendo archivo de etapas:\n%s\n', rutaResumen);
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

fprintf('\nCarpeta de postprocesamiento seleccionada:\n%s\n', carpetaRDS_TJ);
drawnow;

archivosRDS_TJ = dir(fullfile(carpetaRDS_TJ, patronArchivosRDS_TJ));

if isempty(archivosRDS_TJ)
    error('No se encontraron archivos con el patron: %s', patronArchivosRDS_TJ);
end

[~, idxOrdArch] = sort({archivosRDS_TJ.name});
archivosRDS_TJ = archivosRDS_TJ(idxOrdArch);

fprintf('\nArchivos encontrados de RDSon/Tj: %d\n', numel(archivosRDS_TJ));
drawnow;

% =========================================================
%  LECTURA DE ARCHIVOS TDUT_TJ_RDSON
% =========================================================
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
%  3) SELECCIONAR ARCHIVO Vth DINAMICO
% =========================================================
[fileVth, pathVth] = uigetfile( ...
    {'*.csv;*.xlsx;*.xls', 'Archivo de Vth dinamico (*.csv, *.xlsx, *.xls)'}, ...
    'Selecciona el archivo VTH_CICLO_SIMPLE.csv');

if isequal(fileVth, 0)
    error('No seleccionaste el archivo de Vth dinamico.');
end

rutaVth = fullfile(pathVth, fileVth);

fprintf('\nLeyendo archivo de Vth dinamico:\n%s\n', rutaVth);
drawnow;

T_vth = leer_tabla_robusta(rutaVth);
T_vth.Properties.VariableNames = matlab.lang.makeValidName(T_vth.Properties.VariableNames);

fprintf('Filas totales Vth: %d\n', height(T_vth));
drawnow;

% =========================================================
%  DETECTAR COLUMNAS DEL RESUMEN
% =========================================================
fprintf('\nDetectando columnas del RESUMEN...\n');
drawnow;

colsResumen = T_resumen.Properties.VariableNames;

colEtapa = buscar_columna(colsResumen, ...
    {'Etapa', 'etapa', 'Stage', 'stage', 'Estado', 'estado'});

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
    error('No se encontro la columna de etapa en RESUMEN.csv.');
end

if isempty(colTiempoIni) || isempty(colTiempoFin)
    error('No se encontraron columnas Tiempo_inicio_s y Tiempo_fin_s en RESUMEN.csv.');
end

if isempty(colCicloIni) || isempty(colCicloFin)
    error('No se encontraron columnas Ciclo_inicio y Ciclo_fin en RESUMEN.csv.');
end

% =========================================================
%  DETECTAR COLUMNAS DE TDUT_TJ_RDSON
% =========================================================
fprintf('Detectando columnas de RDSon/Tj...\n');
drawnow;

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
    error('No se encontro columna de tiempo en los archivos TDUT_TJ_RDSON.');
end

if isempty(colRDSon)
    error('No se encontro columna de RDSon en los archivos TDUT_TJ_RDSON.');
end

if isempty(colTj)
    error('No se encontro columna de Tj en los archivos TDUT_TJ_RDSON.');
end

% =========================================================
%  DETECTAR COLUMNAS DE Vth
% =========================================================
fprintf('Detectando columnas de Vth...\n');
drawnow;

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
%  EXTRAER ETAPAS DEL RESUMEN
% =========================================================
fprintf('\nExtrayendo etapas...\n');
drawnow;

etapaRaw = T_resumen.(colEtapa);
etapas = convertir_etapas_a_numero(etapaRaw);

tIni = limpiar_vector_numerico(T_resumen.(colTiempoIni));
tFin = limpiar_vector_numerico(T_resumen.(colTiempoFin));

cIni = limpiar_vector_numerico(T_resumen.(colCicloIni));
cFin = limpiar_vector_numerico(T_resumen.(colCicloFin));

maskEtapas = isfinite(etapas) & ...
             isfinite(tIni) & isfinite(tFin) & ...
             isfinite(cIni) & isfinite(cFin);

etapas = etapas(maskEtapas);
tIni   = tIni(maskEtapas);
tFin   = tFin(maskEtapas);
cIni   = cIni(maskEtapas);
cFin   = cFin(maskEtapas);

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

fprintf('\nEtapas validas encontradas:\n');

for e = 1:numEtapas
    idx = find(etapas == e);

    if isempty(idx)
        error('No se encontro la etapa %d en el RESUMEN.csv.', e);
    end

    fprintf('Etapa %d: %.3f s a %.3f s | Ciclos %.0f a %.0f\n', ...
        e, min(tIni(idx)), max(tFin(idx)), min(cIni(idx)), max(cFin(idx)));
end

drawnow;

% =========================================================
%  EXTRAER Y LIMPIAR RDSon Y Tj
% =========================================================
fprintf('\n=============================================\n');
fprintf('EXTRAYENDO RDSon Y Tj...\n');
fprintf('=============================================\n');
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
    warning('No se encontro MascaraRDSon. Se usaran todos los RDSon finitos.');
    maskRDSonBase = isfinite(tDatos) & isfinite(rdson);
end

maskTjBase = isfinite(tDatos) & isfinite(tj);

tRDSon = tDatos(maskRDSonBase);
rdson  = rdson(maskRDSonBase);

tTj = tDatos(maskTjBase);
tj  = tj(maskTjBase);

clear tDatos T_datos;

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

fprintf('RDSon validos finales: %d\n', numel(tRDSon));
fprintf('Tj validos finales:    %d\n', numel(tTj));
drawnow;

% =========================================================
%  EXTRAER Vth POR CICLO
% =========================================================
fprintf('\n=============================================\n');
fprintf('EXTRAYENDO Vth POR CICLO...\n');
fprintf('=============================================\n');
drawnow;

cicloVth = limpiar_vector_numerico(T_vth.(colCicloVth));
vth      = limpiar_vector_numerico(T_vth.(colVth));

if ~isempty(colEstadoVth)
    estadoVth = lower(string(T_vth.(colEstadoVth)));
else
    estadoVth = strings(size(vth));
end

vth = rellenar_nan_con_vecinos(vth);

maskVthBase = isfinite(cicloVth) & isfinite(vth);

cicloVth  = cicloVth(maskVthBase);
vth       = vth(maskVthBase);
estadoVth = estadoVth(maskVthBase);

[cicloVth, idxOrdV] = sort(cicloVth);
vth       = vth(idxOrdV);
estadoVth = estadoVth(idxOrdV);

[cicloVth, vth] = compactar_vth_por_ciclo(cicloVth, vth, estadoVth);

vth = rellenar_nan_con_vecinos(vth);

fprintf('Vth validos finales: %d\n', numel(cicloVth));
drawnow;

clear T_vth;

% =========================================================
%  CONSTRUIR TABLA POR CICLO
% =========================================================
fprintf('\n=============================================\n');
fprintf('CONSTRUYENDO TABLA POR CICLO REAL...\n');
fprintf('=============================================\n');
drawnow;

cicloMin = ceil(min(cIni));
cicloMax = floor(max(cFin));

ciclos = (cicloMin:cicloMax).';

numCiclos = numel(ciclos);

TiempoInicio_s = nan(numCiclos, 1);
TiempoFin_s    = nan(numCiclos, 1);

RDSon_prom_Ohm = nan(numCiclos, 1);
Tj_prom_C      = nan(numCiclos, 1);
Vth_dinamico_V = nan(numCiclos, 1);
Etapa          = nan(numCiclos, 1);

for i = 1:numCiclos

    cicloActual = ciclos(i);

    t_ini_ciclo = tiempoOffset_s + (cicloActual - cicloReferencia) * Tperiodo_s;
    t_fin_ciclo = t_ini_ciclo + Tperiodo_s;

    TiempoInicio_s(i) = t_ini_ciclo;
    TiempoFin_s(i)    = t_fin_ciclo;

    Etapa(i) = obtener_etapa_del_ciclo(cicloActual, t_ini_ciclo, t_fin_ciclo, ...
                                       etapas, cIni, cFin, tIni, tFin);

    t_ini_rds = t_ini_ciclo + ventanaRDS_ini_s;
    t_fin_rds = t_ini_ciclo + ventanaRDS_fin_s;

    maskRDS = tRDSon >= t_ini_rds & tRDSon <= t_fin_rds & isfinite(rdson);

    if any(maskRDS)
        RDSon_prom_Ohm(i) = mean(rdson(maskRDS), 'omitnan');
    else
        RDSon_prom_Ohm(i) = NaN;
    end

    maskTJ = tTj >= t_ini_ciclo & tTj < t_fin_ciclo & isfinite(tj);

    if any(maskTJ)
        Tj_prom_C(i) = mean(tj(maskTJ), 'omitnan');
    else
        Tj_prom_C(i) = NaN;
    end

    idxV = cicloVth == cicloActual;

    if any(idxV)
        Vth_dinamico_V(i) = median(vth(idxV), 'omitnan');
    else
        Vth_dinamico_V(i) = NaN;
    end

    if mod(i, 500) == 0
        fprintf('Ciclos procesados: %d/%d\n', i, numCiclos);
        drawnow;
    end
end

DATA_POR_CICLO = table( ...
    ciclos, ...
    TiempoInicio_s, ...
    TiempoFin_s, ...
    RDSon_prom_Ohm, ...
    Vth_dinamico_V, ...
    Tj_prom_C, ...
    Etapa);

DATA_POR_CICLO.Properties.VariableNames = { ...
    'Ciclo', ...
    'TiempoInicio_s', ...
    'TiempoFin_s', ...
    'RDSon_prom_Ohm', ...
    'Vth_dinamico_V', ...
    'Tj_prom_C', ...
    'Etapa'};

% =========================================================
%  VALIDAR CICLOS
% =========================================================
idxEtapa4 = DATA_POR_CICLO.Etapa == 4;

idxRDSonFaltanteEtapa4 = idxEtapa4 & ~isfinite(DATA_POR_CICLO.RDSon_prom_Ohm);
DATA_POR_CICLO.RDSon_prom_Ohm(idxRDSonFaltanteEtapa4) = 0;

idxVthFaltanteEtapa4 = idxEtapa4 & ~isfinite(DATA_POR_CICLO.Vth_dinamico_V);
DATA_POR_CICLO.Vth_dinamico_V(idxVthFaltanteEtapa4) = 0;

maskEtapas123 = DATA_POR_CICLO.Etapa >= 1 & DATA_POR_CICLO.Etapa <= 3;

maskValido123 = ...
    maskEtapas123 & ...
    isfinite(DATA_POR_CICLO.Ciclo) & ...
    isfinite(DATA_POR_CICLO.RDSon_prom_Ohm) & ...
    isfinite(DATA_POR_CICLO.Vth_dinamico_V) & ...
    isfinite(DATA_POR_CICLO.Tj_prom_C) & ...
    isfinite(DATA_POR_CICLO.Etapa);

maskValido4 = ...
    idxEtapa4 & ...
    isfinite(DATA_POR_CICLO.Ciclo) & ...
    isfinite(DATA_POR_CICLO.Tj_prom_C) & ...
    isfinite(DATA_POR_CICLO.Etapa);

maskCicloCompleto = maskValido123 | maskValido4;

DATA_POR_CICLO.ValidoDataset = maskCicloCompleto;

fprintf('\nResumen de ciclos por etapa antes de balancear:\n');

for e = 1:numEtapas
    nTot = sum(DATA_POR_CICLO.Etapa == e);
    nVal = sum(DATA_POR_CICLO.Etapa == e & DATA_POR_CICLO.ValidoDataset == true);

    fprintf('Etapa %d: ciclos totales = %d | ciclos validos = %d\n', ...
        e, nTot, nVal);
end

fprintf('\nEtapa 4: RDSon faltantes convertidos a 0: %d\n', sum(idxRDSonFaltanteEtapa4));
fprintf('Etapa 4: Vth faltantes convertidos a 0:   %d\n', sum(idxVthFaltanteEtapa4));

drawnow;

% =========================================================
%  GUARDAR DATA_POR_CICLO
% =========================================================
DATA_POR_CICLO_GUARDAR = DATA_POR_CICLO;

DATA_POR_CICLO_GUARDAR.RDSon_prom_Ohm = reemplazar_nan_inf_por_cero(DATA_POR_CICLO_GUARDAR.RDSon_prom_Ohm);
DATA_POR_CICLO_GUARDAR.Vth_dinamico_V = reemplazar_nan_inf_por_cero(DATA_POR_CICLO_GUARDAR.Vth_dinamico_V);
DATA_POR_CICLO_GUARDAR.Tj_prom_C      = reemplazar_nan_inf_por_cero(DATA_POR_CICLO_GUARDAR.Tj_prom_C);
DATA_POR_CICLO_GUARDAR.Etapa          = reemplazar_nan_inf_por_cero(DATA_POR_CICLO_GUARDAR.Etapa);
DATA_POR_CICLO_GUARDAR.ValidoDataset  = DATA_POR_CICLO.ValidoDataset;

rutaPorCiclo = fullfile(carpetaRDS_TJ, nombreSalidaPorCiclo);
writetable(DATA_POR_CICLO_GUARDAR, rutaPorCiclo);

fprintf('\nTabla por ciclo guardada en:\n%s\n', rutaPorCiclo);
drawnow;

% =========================================================
%  GENERAR DATASET BALANCEADO POR ETAPA
% =========================================================
fprintf('\n=============================================\n');
fprintf('GENERANDO DATASET KNN BALANCEADO POR CICLO...\n');
fprintf('=============================================\n');
drawnow;

N_total = numEtapas * N_por_etapa;

CicloDataset = zeros(N_total, 1);

valorRDSon = zeros(N_total, 1);
clasificacionRDSon = zeros(N_total, 1);

valorVth = zeros(N_total, 1);
clasificacionVth = zeros(N_total, 1);

valorTj = zeros(N_total, 1);
clasificacionTj = zeros(N_total, 1);

filaIni = 1;

for etapaActual = 1:numEtapas

    fprintf('\nProcesando etapa %d...\n', etapaActual);
    drawnow;

    maskEtapa = DATA_POR_CICLO.Etapa == etapaActual & ...
                DATA_POR_CICLO.ValidoDataset == true;

    tablaEtapa = DATA_POR_CICLO(maskEtapa, :);

    if height(tablaEtapa) < 2
        error('La etapa %d tiene muy pocos ciclos validos. Revisa DATA_POR_CICLO.csv.', etapaActual);
    end

    idxSel = seleccionar_indices_uniformes(height(tablaEtapa), N_por_etapa);

    tablaSel = tablaEtapa(idxSel, :);

    filaFin = filaIni + N_por_etapa - 1;

    CicloDataset(filaIni:filaFin) = tablaSel.Ciclo;

    valorRDSon(filaIni:filaFin) = tablaSel.RDSon_prom_Ohm;
    clasificacionRDSon(filaIni:filaFin) = etapaActual;

    valorVth(filaIni:filaFin) = tablaSel.Vth_dinamico_V;
    clasificacionVth(filaIni:filaFin) = etapaActual;

    valorTj(filaIni:filaFin) = tablaSel.Tj_prom_C;
    clasificacionTj(filaIni:filaFin) = etapaActual;

    fprintf('Ciclos validos disponibles: %d -> seleccionados: %d\n', ...
        height(tablaEtapa), N_por_etapa);

    fprintf('Ciclo inicial usado: %.0f | Ciclo final usado: %.0f\n', ...
        min(tablaSel.Ciclo), max(tablaSel.Ciclo));

    drawnow;

    filaIni = filaFin + 1;
end

% =========================================================
%  REEMPLAZAR NaN/Inf POR 0 EN DATASET FINAL
% =========================================================
valorRDSon = reemplazar_nan_inf_por_cero(valorRDSon);
valorVth   = reemplazar_nan_inf_por_cero(valorVth);
valorTj    = reemplazar_nan_inf_por_cero(valorTj);

CicloDataset = reemplazar_nan_inf_por_cero(CicloDataset);
clasificacionRDSon = reemplazar_nan_inf_por_cero(clasificacionRDSon);
clasificacionVth   = reemplazar_nan_inf_por_cero(clasificacionVth);
clasificacionTj    = reemplazar_nan_inf_por_cero(clasificacionTj);

% =========================================================
%  TABLAS FINALES CON NOMBRES COMPATIBLES CON PYTHON
% =========================================================
datasetKNN = table( ...
    valorRDSon, clasificacionRDSon, ...
    valorVth,   clasificacionVth, ...
    valorTj,    clasificacionTj);

datasetKNN_conCiclo = table( ...
    CicloDataset, ...
    valorRDSon, clasificacionRDSon, ...
    valorVth,   clasificacionVth, ...
    valorTj,    clasificacionTj);

datasetKNN_conCiclo.Properties.VariableNames{1} = 'Ciclo';

% =========================================================
%  GUARDAR CSV
% =========================================================
rutaSalidaTrain = fullfile(carpetaRDS_TJ, nombreSalidaTrain);
rutaSalidaTrainConCiclo = fullfile(carpetaRDS_TJ, nombreSalidaTrainConCiclo);

fprintf('\nGuardando CSV final...\n');
drawnow;

writetable(datasetKNN, rutaSalidaTrain);
writetable(datasetKNN_conCiclo, rutaSalidaTrainConCiclo);

% =========================================================
%  MENSAJE FINAL
% =========================================================
fprintf('\n=============================================\n');
fprintf('DATASET KNN GENERADO CORRECTAMENTE\n');
fprintf('=============================================\n');
fprintf('Filas totales DATA_TRAIN: %d\n', height(datasetKNN));
fprintf('Datos por etapa: %d\n', N_por_etapa);
fprintf('Numero de etapas: %d\n', numEtapas);
fprintf('\nDATA_POR_CICLO guardado en:\n%s\n', rutaPorCiclo);
fprintf('\nDATA_TRAIN guardado en:\n%s\n', rutaSalidaTrain);
fprintf('\nDATA_TRAIN_CON_CICLO guardado en:\n%s\n', rutaSalidaTrainConCiclo);
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
            vU(k) = median(valsOK, 'omitnan');
        else
            valsValidos = vals(isfinite(vals));

            if ~isempty(valsValidos)
                vU(k) = median(valsValidos, 'omitnan');
            else
                vU(k) = NaN;
            end
        end
    end

    vU = rellenar_nan_con_vecinos(vU);
end

function etapaCiclo = obtener_etapa_del_ciclo(cicloActual, tIniCiclo, tFinCiclo, ...
                                              etapas, cIni, cFin, tIni, tFin)

    etapaCiclo = NaN;

    idxPorCiclo = find(cicloActual >= cIni & cicloActual <= cFin & isfinite(etapas), 1, 'first');

    if ~isempty(idxPorCiclo)
        etapaCiclo = etapas(idxPorCiclo);
        return;
    end

    tMedio = (tIniCiclo + tFinCiclo) / 2;

    idxPorTiempo = find(tMedio >= tIni & tMedio <= tFin & isfinite(etapas), 1, 'first');

    if ~isempty(idxPorTiempo)
        etapaCiclo = etapas(idxPorTiempo);
        return;
    end
end

function idxSel = seleccionar_indices_uniformes(nDisponible, N)

    if nDisponible <= 0
        error('No hay datos disponibles para seleccionar.');
    end

    if nDisponible == 1
        idxSel = ones(N, 1);
        return;
    end

    idxSel = round(linspace(1, nDisponible, N)).';
    idxSel(idxSel < 1) = 1;
    idxSel(idxSel > nDisponible) = nDisponible;
end

function x = reemplazar_nan_inf_por_cero(x)

    x(~isfinite(x)) = 0;

end