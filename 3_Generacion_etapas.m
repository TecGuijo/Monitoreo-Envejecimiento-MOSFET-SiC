clc
clear
clearvars
close all

% =========================================================
% ANALISIS AUTOMATICO DE ETAPAS DESDE TEMP_CARCASA_COMPLETA
% =========================================================
% Etapas:
% 0) Transitorio inicial
% 1) Estabilidad termica
% 2) Creacion / propagacion de grietas
% 3) Falla
% 4) Post-falla
%
% La etapa 4 inicia en el punto maximo de temperatura suavizada
% posterior al inicio de falla.
% =========================================================

% =========================================================
% CONFIGURACION DEL PERFIL
% =========================================================
Ton_s  = 15;
Toff_s = 15;
Tciclo_s = Ton_s + Toff_s;

% =========================================================
% CONFIGURACION DE DETECCION
% =========================================================
cfg = struct();

% Inicio del analisis
cfg.fraccionIgnorarInicial = 0.005;

% Ventanas relativas al tiempo total
cfg.fracVentanaSuavizado = 0.006;
cfg.fracVentanaPendiente = 0.012;

cfg.ventanaSuavizado_min_s = 300;
cfg.ventanaSuavizado_max_s = 3600;

cfg.ventanaPendiente_min_s = 600;
cfg.ventanaPendiente_max_s = 7200;

% Duraciones sostenidas
cfg.fracDuracionEstable = 0.006;
cfg.fracDuracionLento   = 0.008;
cfg.fracDuracionFalla   = 0.003;

cfg.duracionEstable_min_s = 900;
cfg.duracionLento_min_s   = 1200;
cfg.duracionFalla_min_s   = 300;

cfg.duracionEstable_max_s = 7200;
cfg.duracionLento_max_s   = 10800;
cfg.duracionFalla_max_s   = 3600;

% Umbrales minimos de pendiente en C/h
cfg.umbralEstable_C_h_min = 0.8;
cfg.umbralLento_C_h_min   = 0.5;
cfg.umbralFalla_C_h_min   = 5.0;

cfg.percentilLento = 65;
cfg.percentilFalla = 92;

% Criterios para estabilidad termica
cfg.umbralEstable_C_h_max = 8.0;
cfg.rangoMesetaEstable_C  = 12.0;
cfg.fracBusquedaEstable   = 0.35;

% Criterios para creacion / propagacion de grietas
cfg.fracIntervaloEstFallaInicioGrietas = 0.50;
cfg.incrementoTempGrietas_C            = 15.0;
cfg.minTiempoDespuesEstableGrietas_s   = 1800;
cfg.margenAntesFalla_s                 = 1200;
cfg.factorPendienteGrietas             = 0.85;

% Criterios para etapa 4: post-falla
cfg.minTiempoDespuesFallaPico_s = 0;
cfg.maxTiempoBusquedaPostFalla_s = 9000;

% Optimizacion de graficas y guardado
cfg.maxPuntosGrafica = 250000;

% Recomendado:
% false = mas rapido. Para otro postproceso normalmente basta TRANS.csv.
% true  = guarda FULL.csv con todos los puntos etiquetados.
cfg.guardarCSVCompleto = false;

% Archivo ligero para Excel
cfg.guardarCSVExcel    = true;
cfg.maxPuntosCSVExcel  = 300000;

% =========================================================
% SELECCIONAR ARCHIVO
% =========================================================
[fileName, filePath] = uigetfile('*.csv', ...
    'Selecciona TEMP_CARCASA_COMPLETA.csv');

if isequal(fileName,0)
    disp('No se selecciono archivo.');
    return
end

archivoTemp = fullfile(filePath, fileName);

fprintf('\n====================================================\n');
fprintf('ANALISIS DE ETAPAS DESDE TEMPERATURA DE CARCASA\n');
fprintf('Archivo: %s\n', archivoTemp);
fprintf('Ton  = %.3f s\n', Ton_s);
fprintf('Toff = %.3f s\n', Toff_s);
fprintf('Tciclo = %.3f s\n', Tciclo_s);
fprintf('====================================================\n\n');

% =========================================================
% CARPETA DE SALIDA
% =========================================================
outputFolder = fullfile(filePath, ...
    ['ET_' datestr(now,'yyyymmdd_HHMMSS')]);

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

fprintf('Carpeta de salida: %s\n\n', outputFolder);

% =========================================================
% LEER SOLO COLUMNAS NECESARIAS
% =========================================================
fprintf('Leyendo archivo...\n');

opts = detectImportOptions(archivoTemp);

colTiempo = detectar_columna_lista(opts.VariableNames, ...
    {'Tiempo_s','TiempoGlobal_s','Time_s','t_s','Tiempo'});

colTemp = detectar_columna_lista(opts.VariableNames, ...
    {'TEMP_CARCASA_C','TDUT_C','TEMP_DUT_C','DUT_C','Temperatura_C','T_DUT_C'});

if isempty(colTiempo)
    error('No se encontro columna de tiempo.');
end

if isempty(colTemp)
    error('No se encontro columna de temperatura de carcasa.');
end

opts.SelectedVariableNames = {colTiempo, colTemp};

T = readtable(archivoTemp, opts);

t = T.(colTiempo)(:);
temp = T.(colTemp)(:);

clear T

idx = isfinite(t) & isfinite(temp);
t = t(idx);
temp = temp(idx);

[t, idxSort] = sort(t);
temp = temp(idxSort);

[t, idxU] = unique(t, 'stable');
temp = temp(idxU);

t = t - t(1);

if numel(t) < 10
    error('No hay suficientes puntos para analizar etapas.');
end

fprintf('Puntos validos: %d\n', numel(t));
fprintf('Duracion total: %.2f s | %.2f h\n\n', t(end), t(end)/3600);

% =========================================================
% DETECTAR ETAPAS
% =========================================================
fprintf('Detectando etapas...\n');

etapas = detectar_etapas_temperatura(t, temp, cfg, Tciclo_s);

% =========================================================
% MOSTRAR RESULTADOS
% =========================================================
fprintf('\n====================================================\n');
fprintf('RESULTADO DE ETAPAS DETECTADAS\n');
fprintf('====================================================\n');

for k = 1:height(etapas.resumenEtapas)
    fprintf('\n%s\n', etapas.resumenEtapas.Etapa(k));
    fprintf('  Tiempo : %.2f s  a  %.2f s\n', ...
        etapas.resumenEtapas.Tiempo_inicio_s(k), ...
        etapas.resumenEtapas.Tiempo_fin_s(k));

    fprintf('  Ciclos : %d  a  %d\n', ...
        etapas.resumenEtapas.Ciclo_inicio(k), ...
        etapas.resumenEtapas.Ciclo_fin(k));

    fprintf('  Temp   : %.2f C  a  %.2f C\n', ...
        etapas.resumenEtapas.Temp_inicio_C(k), ...
        etapas.resumenEtapas.Temp_fin_C(k));

    fprintf('  Duracion: %.2f h\n', ...
        etapas.resumenEtapas.Duracion_h(k));
end

fprintf('\n====================================================\n');
fprintf('PUNTOS DE TRANSICION\n');
fprintf('====================================================\n');
fprintf('Inicio estabilidad : %.2f s | ciclo %d | %.2f C\n', ...
    etapas.tEst_s, etapas.cicloEst, etapas.tempEst_C);
fprintf('Inicio grietas     : %.2f s | ciclo %d | %.2f C\n', ...
    etapas.tGri_s, etapas.cicloGri, etapas.tempGri_C);
fprintf('Inicio falla       : %.2f s | ciclo %d | %.2f C\n', ...
    etapas.tFal_s, etapas.cicloFal, etapas.tempFal_C);
fprintf('Inicio post-falla  : %.2f s | ciclo %d | %.2f C\n', ...
    etapas.tEt4_s, etapas.cicloEt4, etapas.tempEt4_C);

% =========================================================
% GUARDAR ARCHIVOS
% =========================================================
fprintf('\nGuardando archivos...\n');

archivoResumen = fullfile(outputFolder, 'RESUMEN.csv');
archivoTrans   = fullfile(outputFolder, 'TRANS.csv');
archivoFull    = fullfile(outputFolder, 'FULL.csv');
archivoExcel   = fullfile(outputFolder, 'EXCEL.csv');
archivoTXT     = fullfile(outputFolder, 'RESUMEN.txt');

% ---------------------------------------------------------
% Guardar resumen
% ---------------------------------------------------------
resumenGuardar = etapas.resumenEtapas;

if isstring(resumenGuardar.Etapa)
    resumenGuardar.Etapa = cellstr(resumenGuardar.Etapa);
end

writetable(resumenGuardar, archivoResumen, 'Delimiter',';');

% ---------------------------------------------------------
% Guardar transiciones para otros postprocesamientos
% ---------------------------------------------------------
transiciones = table( ...
    etapas.tEst_s, ...
    etapas.tGri_s, ...
    etapas.tFal_s, ...
    etapas.tEt4_s, ...
    etapas.cicloEst, ...
    etapas.cicloGri, ...
    etapas.cicloFal, ...
    etapas.cicloEt4, ...
    etapas.tempEst_C, ...
    etapas.tempGri_C, ...
    etapas.tempFal_C, ...
    etapas.tempEt4_C, ...
    'VariableNames', { ...
    'Inicio_estabilidad_s', ...
    'Inicio_grietas_s', ...
    'Inicio_falla_s', ...
    'Inicio_post_falla_s', ...
    'Ciclo_estabilidad', ...
    'Ciclo_grietas', ...
    'Ciclo_falla', ...
    'Ciclo_post_falla', ...
    'Temp_estabilidad_C', ...
    'Temp_grietas_C', ...
    'Temp_falla_C', ...
    'Temp_post_falla_C'} );

writetable(transiciones, archivoTrans, 'Delimiter',';');

% ---------------------------------------------------------
% Crear datos etiquetados solo si hace falta guardar FULL o EXCEL
% ---------------------------------------------------------
if cfg.guardarCSVCompleto || cfg.guardarCSVExcel

    datosGuardar = etapas.datosEtiquetados;

    if isstring(datosGuardar.Etapa)
        datosGuardar.Etapa = cellstr(datosGuardar.Etapa);
    end

    if cfg.guardarCSVCompleto
        writetable(datosGuardar, archivoFull, 'Delimiter',';');
        fprintf('CSV completo guardado: %s\n', archivoFull);
    else
        fprintf('CSV completo no guardado para acelerar el proceso.\n');
    end

    if cfg.guardarCSVExcel

        nFilas = height(datosGuardar);

        if nFilas > cfg.maxPuntosCSVExcel
            idxCSV = obtener_indices_grafica(nFilas, cfg.maxPuntosCSVExcel);
            datosExcel = datosGuardar(idxCSV,:);
        else
            idxCSV = 1:nFilas;
            datosExcel = datosGuardar;
        end

        writetable(datosExcel, archivoExcel, 'Delimiter',';');

        fprintf('CSV para Excel guardado: %s\n', archivoExcel);
        fprintf('Filas en CSV Excel: %d de %d\n', numel(idxCSV), nFilas);
    end
end

% ---------------------------------------------------------
% Guardar TXT
% ---------------------------------------------------------
fid = fopen(archivoTXT, 'w');

if fid > 0
    fprintf(fid, 'ANALISIS DE ETAPAS DESDE TEMPERATURA DE CARCASA\n');
    fprintf(fid, 'Fecha: %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'Archivo origen: %s\n', archivoTemp);
    fprintf(fid, 'Ton_s: %.9f\n', Ton_s);
    fprintf(fid, 'Toff_s: %.9f\n', Toff_s);
    fprintf(fid, 'Tciclo_s: %.9f\n\n', Tciclo_s);

    fprintf(fid, 'PUNTOS DE TRANSICION\n');
    fprintf(fid, 'Inicio estabilidad_s: %.9f\n', etapas.tEst_s);
    fprintf(fid, 'Inicio estabilidad_ciclo: %d\n', etapas.cicloEst);
    fprintf(fid, 'Inicio estabilidad_temp_C: %.9f\n\n', etapas.tempEst_C);

    fprintf(fid, 'Inicio grietas_s: %.9f\n', etapas.tGri_s);
    fprintf(fid, 'Inicio grietas_ciclo: %d\n', etapas.cicloGri);
    fprintf(fid, 'Inicio grietas_temp_C: %.9f\n\n', etapas.tempGri_C);

    fprintf(fid, 'Inicio falla_s: %.9f\n', etapas.tFal_s);
    fprintf(fid, 'Inicio falla_ciclo: %d\n', etapas.cicloFal);
    fprintf(fid, 'Inicio falla_temp_C: %.9f\n\n', etapas.tempFal_C);

    fprintf(fid, 'Inicio post_falla_s: %.9f\n', etapas.tEt4_s);
    fprintf(fid, 'Inicio post_falla_ciclo: %d\n', etapas.cicloEt4);
    fprintf(fid, 'Inicio post_falla_temp_C: %.9f\n\n', etapas.tempEt4_C);

    fprintf(fid, 'UMBRALES\n');
    fprintf(fid, 'Umbral estabilidad_C_h: %.9f\n', etapas.umbralEstable_C_h);
    fprintf(fid, 'Umbral estabilidad max_C_h: %.9f\n', cfg.umbralEstable_C_h_max);
    fprintf(fid, 'Rango meseta estable_C: %.9f\n', cfg.rangoMesetaEstable_C);
    fprintf(fid, 'Umbral grietas_C_h: %.9f\n', etapas.umbralLento_C_h);
    fprintf(fid, 'Umbral falla_C_h: %.9f\n\n', etapas.umbralFalla_C_h);

    fprintf(fid, 'CONFIGURACION GRIETAS\n');
    fprintf(fid, 'fracIntervaloEstFallaInicioGrietas: %.9f\n', cfg.fracIntervaloEstFallaInicioGrietas);
    fprintf(fid, 'incrementoTempGrietas_C: %.9f\n', cfg.incrementoTempGrietas_C);
    fprintf(fid, 'minTiempoDespuesEstableGrietas_s: %.9f\n', cfg.minTiempoDespuesEstableGrietas_s);
    fprintf(fid, 'margenAntesFalla_s: %.9f\n', cfg.margenAntesFalla_s);
    fprintf(fid, 'factorPendienteGrietas: %.9f\n\n', cfg.factorPendienteGrietas);

    fprintf(fid, 'CONFIGURACION POST-FALLA\n');
    fprintf(fid, 'minTiempoDespuesFallaPico_s: %.9f\n', cfg.minTiempoDespuesFallaPico_s);
    fprintf(fid, 'maxTiempoBusquedaPostFalla_s: %.9f\n\n', cfg.maxTiempoBusquedaPostFalla_s);

    fprintf(fid, 'VENTANAS\n');
    fprintf(fid, 'Ventana suavizado_s: %.9f\n', etapas.ventanaSuavizado_s);
    fprintf(fid, 'Ventana pendiente_s: %.9f\n\n', etapas.ventanaPendiente_s);

    fprintf(fid, 'GUARDADO\n');
    fprintf(fid, 'Carpeta salida: %s\n', outputFolder);
    fprintf(fid, 'guardarCSVCompleto: %d\n', cfg.guardarCSVCompleto);
    fprintf(fid, 'guardarCSVExcel: %d\n', cfg.guardarCSVExcel);
    fprintf(fid, 'maxPuntosCSVExcel: %d\n\n', cfg.maxPuntosCSVExcel);

    fprintf(fid, 'RESUMEN POR ETAPA\n');

    for k = 1:height(etapas.resumenEtapas)
        fprintf(fid, '\n%s\n', etapas.resumenEtapas.Etapa(k));
        fprintf(fid, 'Tiempo_inicio_s: %.9f\n', etapas.resumenEtapas.Tiempo_inicio_s(k));
        fprintf(fid, 'Tiempo_fin_s: %.9f\n', etapas.resumenEtapas.Tiempo_fin_s(k));
        fprintf(fid, 'Ciclo_inicio: %d\n', etapas.resumenEtapas.Ciclo_inicio(k));
        fprintf(fid, 'Ciclo_fin: %d\n', etapas.resumenEtapas.Ciclo_fin(k));
        fprintf(fid, 'Temp_inicio_C: %.9f\n', etapas.resumenEtapas.Temp_inicio_C(k));
        fprintf(fid, 'Temp_fin_C: %.9f\n', etapas.resumenEtapas.Temp_fin_C(k));
        fprintf(fid, 'Duracion_s: %.9f\n', etapas.resumenEtapas.Duracion_s(k));
        fprintf(fid, 'Duracion_h: %.9f\n', etapas.resumenEtapas.Duracion_h(k));
    end

    fclose(fid);
end

% =========================================================
% GRAFICA
% =========================================================
fprintf('Generando grafica...\n');

idxPlot = obtener_indices_grafica(numel(t), cfg.maxPuntosGrafica);

tPlot    = t(idxPlot);
tempPlot = temp(idxPlot);
suavPlot = etapas.tempSuavizada(idxPlot);

fig1 = figure('Name','Etapas desde temperatura de carcasa','NumberTitle','off');
set(fig1, 'Color', 'w');

hold on
grid on
box on

hTemp = plot(tPlot, tempPlot, 'LineWidth', 0.8, ...
    'DisplayName','Temperatura carcasa');

hSuav = plot(tPlot, suavPlot, 'k', 'LineWidth', 1.5, ...
    'DisplayName','Temperatura suavizada');

yl = ylim;

hEst = patch([etapas.tEst_s etapas.tGri_s etapas.tGri_s etapas.tEst_s], ...
      [yl(1) yl(1) yl(2) yl(2)], ...
      [0.85 1.00 0.85], ...
      'FaceAlpha',0.18, 'EdgeColor','none', ...
      'DisplayName','Estabilidad termica');

hGri = patch([etapas.tGri_s etapas.tFal_s etapas.tFal_s etapas.tGri_s], ...
      [yl(1) yl(1) yl(2) yl(2)], ...
      [1.00 0.95 0.70], ...
      'FaceAlpha',0.18, 'EdgeColor','none', ...
      'DisplayName','Creacion de grietas');

hFal = patch([etapas.tFal_s etapas.tEt4_s etapas.tEt4_s etapas.tFal_s], ...
      [yl(1) yl(1) yl(2) yl(2)], ...
      [1.00 0.80 0.80], ...
      'FaceAlpha',0.18, 'EdgeColor','none', ...
      'DisplayName','Falla');

hEt4 = patch([etapas.tEt4_s t(end) t(end) etapas.tEt4_s], ...
      [yl(1) yl(1) yl(2) yl(2)], ...
      [0.85 0.85 1.00], ...
      'FaceAlpha',0.18, 'EdgeColor','none', ...
      'DisplayName','Post-falla');

uistack(hEst, 'bottom');
uistack(hGri, 'bottom');
uistack(hFal, 'bottom');
uistack(hEt4, 'bottom');
uistack(hTemp, 'top');
uistack(hSuav, 'top');

xline(etapas.tEst_s, '--', sprintf('Estabilidad | ciclo %d', etapas.cicloEst), ...
    'LabelOrientation','horizontal', ...
    'LabelVerticalAlignment','bottom');

xline(etapas.tGri_s, '--', sprintf('Grietas | ciclo %d', etapas.cicloGri), ...
    'LabelOrientation','horizontal', ...
    'LabelVerticalAlignment','bottom');

xline(etapas.tFal_s, '--', sprintf('Falla | ciclo %d', etapas.cicloFal), ...
    'LabelOrientation','horizontal', ...
    'LabelVerticalAlignment','bottom');

xline(etapas.tEt4_s, '--', sprintf('Post-falla | ciclo %d', etapas.cicloEt4), ...
    'LabelOrientation','horizontal', ...
    'LabelVerticalAlignment','bottom');

xlabel('Tiempo (s)');
ylabel('Temperatura de carcasa (°C)');
title('Segmentacion automatica de etapas por temperatura de carcasa');

legend([hEst hGri hFal hEt4 hTemp hSuav], ...
    {'Estabilidad termica','Creacion de grietas','Falla', ...
    'Post-falla','Temperatura carcasa','Temperatura suavizada'}, ...
    'Location','best');

hold off

saveas(fig1, fullfile(outputFolder, 'GRAFICA.png'));
savefig(fig1, fullfile(outputFolder, 'GRAFICA.fig'));

fprintf('\n====================================================\n');
fprintf('ANALISIS FINALIZADO\n');
fprintf('Resumen CSV: %s\n', archivoResumen);
fprintf('Transiciones CSV: %s\n', archivoTrans);

if cfg.guardarCSVCompleto
    fprintf('Datos etiquetados completo: %s\n', archivoFull);
end

if cfg.guardarCSVExcel
    fprintf('Datos etiquetados Excel: %s\n', archivoExcel);
end

fprintf('Resumen TXT: %s\n', archivoTXT);
fprintf('Grafica PNG: %s\n', fullfile(outputFolder, 'GRAFICA.png'));
fprintf('Carpeta salida: %s\n', outputFolder);
fprintf('====================================================\n');

% =========================================================
% FUNCIONES LOCALES
% =========================================================

function etapas = detectar_etapas_temperatura(t, temp, cfg, Tciclo_s)

    t = t(:);
    temp = temp(:);

    idx = isfinite(t) & isfinite(temp);
    t = t(idx);
    temp = temp(idx);

    [t, idxSort] = sort(t);
    temp = temp(idxSort);

    [t, idxU] = unique(t, 'stable');
    temp = temp(idxU);

    t = t - t(1);

    n = numel(t);
    tiempoTotal_s = t(end) - t(1);

    dtMediana = median(diff(t), 'omitnan');

    if ~isfinite(dtMediana) || dtMediana <= 0
        dtMediana = mean(diff(t), 'omitnan');
    end

    if ~isfinite(dtMediana) || dtMediana <= 0
        error('No se pudo calcular dtMediana.');
    end

    ventanaSuavizado_s = limitar_valor( ...
        cfg.fracVentanaSuavizado * tiempoTotal_s, ...
        cfg.ventanaSuavizado_min_s, ...
        cfg.ventanaSuavizado_max_s);

    ventanaPendiente_s = limitar_valor( ...
        cfg.fracVentanaPendiente * tiempoTotal_s, ...
        cfg.ventanaPendiente_min_s, ...
        cfg.ventanaPendiente_max_s);

    duracionEstable_s = limitar_valor( ...
        cfg.fracDuracionEstable * tiempoTotal_s, ...
        cfg.duracionEstable_min_s, ...
        cfg.duracionEstable_max_s);

    duracionLento_s = limitar_valor( ...
        cfg.fracDuracionLento * tiempoTotal_s, ...
        cfg.duracionLento_min_s, ...
        cfg.duracionLento_max_s);

    duracionFalla_s = limitar_valor( ...
        cfg.fracDuracionFalla * tiempoTotal_s, ...
        cfg.duracionFalla_min_s, ...
        cfg.duracionFalla_max_s);

    Nsuav = max(5, round(ventanaSuavizado_s / dtMediana));
    Npend = max(5, round(ventanaPendiente_s / dtMediana));

    Nestable = max(5, round(duracionEstable_s / dtMediana));
    Nlento   = max(5, round(duracionLento_s / dtMediana));
    Nfalla   = max(5, round(duracionFalla_s / dtMediana));

    Nmax = max(5, floor(n / 8));

    Nsuav = min(Nsuav, Nmax);
    Npend = min(Npend, Nmax);

    Nestable = min(Nestable, Nmax);
    Nlento   = min(Nlento, Nmax);
    Nfalla   = min(Nfalla, Nmax);

    tempSuav = movmedian(temp, Nsuav, 'omitnan');
    tempSuav = movmean(tempSuav, Nsuav, 'omitnan');

    dTdt_C_s = gradient(tempSuav, t);
    pendienteRaw_C_h = dTdt_C_s * 3600;

    pendiente_C_h = movmedian(pendienteRaw_C_h, Npend, 'omitnan');
    pendiente_C_h = movmean(pendiente_C_h, Npend, 'omitnan');

    idxInicioAnalisis = max(1, round(cfg.fraccionIgnorarInicial * n));
    idxInicioAnalisis = min(idxInicioAnalisis, n - 5);

    pendAnalisis = pendiente_C_h(idxInicioAnalisis:end);
    pendAnalisis = pendAnalisis(isfinite(pendAnalisis));

    if isempty(pendAnalisis)
        error('No hay pendiente valida para detectar etapas.');
    end

    umbralEstable_C_h = cfg.umbralEstable_C_h_min;

    umbralLento_C_h = prctile(pendAnalisis, cfg.percentilLento);
    umbralFalla_C_h = prctile(pendAnalisis, cfg.percentilFalla);

    umbralLento_C_h = max(umbralLento_C_h, cfg.umbralLento_C_h_min);
    umbralFalla_C_h = max(umbralFalla_C_h, cfg.umbralFalla_C_h_min);

    if umbralFalla_C_h <= 2.5 * umbralLento_C_h
        umbralFalla_C_h = 2.5 * umbralLento_C_h;
    end

    % Estabilidad
    idxEst = detectar_inicio_estabilidad_meseta( ...
        t, tempSuav, pendiente_C_h, idxInicioAnalisis, ...
        Nestable, cfg);

    if isnan(idxEst)
        condEstable = abs(pendiente_C_h) <= cfg.umbralEstable_C_h_max;
        idxEst = buscar_condicion_sostenida(condEstable, idxInicioAnalisis, Nestable);
    end

    if isnan(idxEst)
        rango = idxInicioAnalisis:min(n, round(cfg.fracBusquedaEstable*n));
        [~, iMin] = min(abs(pendiente_C_h(rango)));
        idxEst = rango(iMin);
    end

    % Grietas base solo para conservar falla
    condLentoBase = pendiente_C_h >= umbralLento_C_h;

    idxGriBase = buscar_condicion_sostenida(condLentoBase, idxEst + Nestable, Nlento);

    if isnan(idxGriBase)
        idxGriBase = detectar_subida_lenta_por_desviacion( ...
            t, tempSuav, pendiente_C_h, idxEst, umbralLento_C_h);
    end

    if isnan(idxGriBase)
        idxGriBase = round(0.60*n);
    end

    % Falla
    condFalla = pendiente_C_h >= umbralFalla_C_h;

    idxFal = buscar_condicion_sostenida(condFalla, idxGriBase + Nlento, Nfalla);

    if isnan(idxFal)
        idxFal = detectar_subida_brusca_por_curvatura( ...
            t, tempSuav, pendiente_C_h, idxGriBase);
    end

    if isnan(idxFal)
        idxFal = round(0.90*n);
    end

    idxFal = max(idxEst + 2, min(idxFal, n));

    % Post-falla por maximo de temperatura suavizada
    idxEt4 = detectar_inicio_post_falla_por_pico_temperatura( ...
        t, tempSuav, idxFal, cfg);

    if isnan(idxEt4)
        idxEt4 = n;
    end

    idxEt4 = max(idxFal + 1, min(idxEt4, n));

    % Grietas corregido
    idxGri = detectar_inicio_grietas_restringido( ...
        t, tempSuav, pendiente_C_h, ...
        idxEst, idxFal, Nestable, Nlento, ...
        umbralLento_C_h, cfg);

    if isnan(idxGri)
        tInicioGrietasFallback = t(idxEst) + ...
            cfg.fracIntervaloEstFallaInicioGrietas * (t(idxFal) - t(idxEst));

        idxGri = buscar_indice_por_tiempo(t, tInicioGrietasFallback);
    end

    tMinGrietas = t(idxEst) + ...
        cfg.fracIntervaloEstFallaInicioGrietas * (t(idxFal) - t(idxEst));

    idxMinGrietas = buscar_indice_por_tiempo(t, tMinGrietas);

    idxMinPorTiempo = buscar_indice_por_tiempo( ...
        t, t(idxEst) + cfg.minTiempoDespuesEstableGrietas_s);

    idxGri = max([idxGri, idxMinGrietas, idxMinPorTiempo, idxEst + 1]);

    idxMargenFalla = buscar_indice_por_tiempo(t, t(idxFal) - cfg.margenAntesFalla_s);

    if idxMargenFalla > idxEst + 1
        idxGri = min(idxGri, idxMargenFalla);
    end

    idxEst = max(1, min(idxEst, n));
    idxGri = max(idxEst + 1, min(idxGri, n));
    idxFal = max(idxGri + 1, min(idxFal, n));
    idxEt4 = max(idxFal + 1, min(idxEt4, n));

    etiqueta = strings(size(t));
    etiqueta(:) = "Transitorio_inicial";

    etiqueta(t >= t(idxEst) & t < t(idxGri)) = "Estabilidad_termica";
    etiqueta(t >= t(idxGri) & t < t(idxFal)) = "Creacion_grietas";
    etiqueta(t >= t(idxFal) & t < t(idxEt4)) = "Falla";
    etiqueta(t >= t(idxEt4))                 = "Post_falla";

    ciclo = floor(t ./ Tciclo_s) + 1;

    datosEtiquetados = table(t, ciclo, temp, tempSuav, pendiente_C_h, etiqueta, ...
        'VariableNames', {'Tiempo_s','Ciclo','TEMP_CARCASA_C', ...
        'TEMP_SUAVIZADA_C','Pendiente_C_h','Etapa'});

    resumenEtapas = crear_resumen_etapas(t, temp, ciclo, etiqueta);

    etapas = struct();

    etapas.t = t;
    etapas.temp = temp;
    etapas.tempSuavizada = tempSuav;
    etapas.pendiente_C_h = pendiente_C_h;

    etapas.idxEst = idxEst;
    etapas.idxGri = idxGri;
    etapas.idxFal = idxFal;
    etapas.idxEt4 = idxEt4;

    etapas.tEst_s = t(idxEst);
    etapas.tGri_s = t(idxGri);
    etapas.tFal_s = t(idxFal);
    etapas.tEt4_s = t(idxEt4);

    etapas.cicloEst = ciclo(idxEst);
    etapas.cicloGri = ciclo(idxGri);
    etapas.cicloFal = ciclo(idxFal);
    etapas.cicloEt4 = ciclo(idxEt4);

    etapas.tempEst_C = temp(idxEst);
    etapas.tempGri_C = temp(idxGri);
    etapas.tempFal_C = temp(idxFal);
    etapas.tempEt4_C = temp(idxEt4);

    etapas.umbralEstable_C_h = umbralEstable_C_h;
    etapas.umbralLento_C_h = umbralLento_C_h;
    etapas.umbralFalla_C_h = umbralFalla_C_h;

    etapas.ventanaSuavizado_s = ventanaSuavizado_s;
    etapas.ventanaPendiente_s = ventanaPendiente_s;

    etapas.resumenEtapas = resumenEtapas;
    etapas.datosEtiquetados = datosEtiquetados;
end

function resumenEtapas = crear_resumen_etapas(t, temp, ciclo, etiqueta)

    nombresEtapa = [
        "Transitorio_inicial"
        "Estabilidad_termica"
        "Creacion_grietas"
        "Falla"
        "Post_falla"
    ];

    Etapa = strings(0,1);
    Tiempo_inicio_s = [];
    Tiempo_fin_s = [];
    Ciclo_inicio = [];
    Ciclo_fin = [];
    Temp_inicio_C = [];
    Temp_fin_C = [];
    Duracion_s = [];
    Duracion_h = [];

    for k = 1:numel(nombresEtapa)

        nom = nombresEtapa(k);
        idxE = find(etiqueta == nom);

        if isempty(idxE)
            continue
        end

        i1 = idxE(1);
        i2 = idxE(end);

        Etapa(end+1,1) = nom;
        Tiempo_inicio_s(end+1,1) = t(i1);
        Tiempo_fin_s(end+1,1) = t(i2);
        Ciclo_inicio(end+1,1) = ciclo(i1);
        Ciclo_fin(end+1,1) = ciclo(i2);
        Temp_inicio_C(end+1,1) = temp(i1);
        Temp_fin_C(end+1,1) = temp(i2);
        Duracion_s(end+1,1) = t(i2) - t(i1);
        Duracion_h(end+1,1) = (t(i2) - t(i1))/3600;
    end

    resumenEtapas = table( ...
        Etapa, Tiempo_inicio_s, Tiempo_fin_s, ...
        Ciclo_inicio, Ciclo_fin, Temp_inicio_C, Temp_fin_C, ...
        Duracion_s, Duracion_h);
end

function idxGri = detectar_inicio_grietas_restringido( ...
    t, tempSuav, pendiente_C_h, ...
    idxEst, idxFal, Nestable, Nlento, ...
    umbralLento_C_h, cfg)

    idxGri = NaN;
    n = numel(t);

    if idxFal <= idxEst + 10
        return
    end

    tMinGrietas = t(idxEst) + ...
        cfg.fracIntervaloEstFallaInicioGrietas * (t(idxFal) - t(idxEst));

    idxPorIntervalo = buscar_indice_por_tiempo(t, tMinGrietas);

    idxPorTiempo = buscar_indice_por_tiempo( ...
        t, t(idxEst) + cfg.minTiempoDespuesEstableGrietas_s);

    idxPorVentana = idxEst + Nestable;

    idxInicio = max([idxPorIntervalo, idxPorTiempo, idxPorVentana, 1]);

    tMax = t(idxFal) - cfg.margenAntesFalla_s;
    idxFin = buscar_indice_por_tiempo(t, tMax);
    idxFin = min(idxFin, idxFal - 1);

    if idxInicio >= idxFin
        return
    end

    idxRefFin = min(idxEst + Nestable, n);
    tempReferencia = median(tempSuav(idxEst:idxRefFin), 'omitnan');

    if ~isfinite(tempReferencia)
        tempReferencia = tempSuav(idxEst);
    end

    condTemp = tempSuav >= tempReferencia + cfg.incrementoTempGrietas_C;
    condPend = pendiente_C_h >= umbralLento_C_h;

    cond = condTemp & condPend;

    cond(1:idxInicio-1) = false;
    cond(idxFin+1:end) = false;

    idxGri = buscar_condicion_sostenida(cond, idxInicio, Nlento);

    if ~isnan(idxGri)
        return
    end

    idxBaseFin = max(idxEst + 10, idxInicio - 1);
    idxBaseFin = min(idxBaseFin, idxFin);

    if idxBaseFin <= idxEst + 10
        return
    end

    tBase = t(idxEst:idxBaseFin);
    yBase = tempSuav(idxEst:idxBaseFin);

    p = polyfit(tBase, yBase, 1);
    yPred = polyval(p, t);

    residuo = tempSuav - yPred;
    residuoBase = residuo(idxEst:idxBaseFin);

    sigmaBase = std(residuoBase, 'omitnan');

    if ~isfinite(sigmaBase) || sigmaBase <= 0
        sigmaBase = 1;
    end

    umbralResiduo = max(3*sigmaBase, 0.40*cfg.incrementoTempGrietas_C);

    condResiduo = residuo >= umbralResiduo;
    condTemp2   = tempSuav >= tempReferencia + 0.70*cfg.incrementoTempGrietas_C;
    condPend2   = pendiente_C_h >= cfg.factorPendienteGrietas * umbralLento_C_h;

    cond2 = condResiduo & condTemp2 & condPend2;

    cond2(1:idxInicio-1) = false;
    cond2(idxFin+1:end) = false;

    idxGri = buscar_condicion_sostenida(cond2, idxInicio, max(5, round(0.70*Nlento)));
end

function idxEt4 = detectar_inicio_post_falla_por_pico_temperatura(t, tempSuav, idxFal, cfg)

    idxEt4 = NaN;

    t = t(:);
    tempSuav = tempSuav(:);

    n = numel(t);

    if idxFal >= n - 5
        return
    end

    tInicioBusqueda = t(idxFal) + cfg.minTiempoDespuesFallaPico_s;
    idxInicio = buscar_indice_por_tiempo(t, tInicioBusqueda);

    idxInicio = max(idxFal + 1, idxInicio);
    idxInicio = min(idxInicio, n);

    if idxInicio >= n
        return
    end

    tFinBusqueda = t(idxFal) + cfg.maxTiempoBusquedaPostFalla_s;
    idxFin = buscar_indice_por_tiempo(t, tFinBusqueda);

    idxFin = min(idxFin, n);

    if idxFin <= idxInicio
        return
    end

    rango = idxInicio:idxFin;

    y = tempSuav(rango);
    y(~isfinite(y)) = -inf;

    if isempty(y) || all(y == -inf)
        return
    end

    [~, iMax] = max(y);

    idxEt4 = rango(iMax);
    idxEt4 = max(idxFal + 1, min(idxEt4, n));
end

function idxEst = detectar_inicio_estabilidad_meseta(t, tempSuav, pendiente_C_h, idxInicioAnalisis, Nestable, cfg)

    idxEst = NaN;
    n = numel(t);

    if n < Nestable || idxInicioAnalisis >= n
        return
    end

    idxFinBusqueda = min(n - Nestable + 1, round(cfg.fracBusquedaEstable * n));

    if idxFinBusqueda <= idxInicioAnalisis
        return
    end

    tempSuav = tempSuav(:);
    pendiente_C_h = pendiente_C_h(:);

    tempMax = movmax(tempSuav, [0 Nestable-1], 'omitnan', 'Endpoints','discard');
    tempMin = movmin(tempSuav, [0 Nestable-1], 'omitnan', 'Endpoints','discard');

    rangoTemp = tempMax - tempMin;

    pendAbs = abs(pendiente_C_h);
    pendMedia = movmean(pendAbs, [0 Nestable-1], 'omitnan', 'Endpoints','discard');

    cond = rangoTemp <= cfg.rangoMesetaEstable_C & ...
           pendMedia <= cfg.umbralEstable_C_h_max;

    idxCandidatos = find(cond);

    idxCandidatos = idxCandidatos(idxCandidatos >= idxInicioAnalisis & ...
                                  idxCandidatos <= idxFinBusqueda);

    if isempty(idxCandidatos)
        return
    end

    idxEst = idxCandidatos(1);
end

function idxInicio = buscar_condicion_sostenida(condicion, idxDesde, N)

    idxInicio = NaN;

    condicion = condicion(:);
    n = numel(condicion);

    idxDesde = max(1, round(idxDesde));
    N = max(1, round(N));

    if n < N || idxDesde > n - N + 1
        return
    end

    condicion = condicion & isfinite(condicion);

    sumaVentana = movsum(double(condicion), [0 N-1], 'Endpoints','discard');

    idxValidos = find(sumaVentana >= N);

    if isempty(idxValidos)
        return
    end

    idxValidos = idxValidos(idxValidos >= idxDesde);

    if isempty(idxValidos)
        return
    end

    idxInicio = idxValidos(1);
end

function idxOut = detectar_subida_lenta_por_desviacion(t, tempSuav, pendiente_C_h, idxEst, umbralLento_C_h)

    idxOut = NaN;

    n = numel(t);

    idxBaseFin = min(n, idxEst + round(0.15*n));

    if idxBaseFin <= idxEst + 10
        return
    end

    tBase = t(idxEst:idxBaseFin);
    yBase = tempSuav(idxEst:idxBaseFin);

    p = polyfit(tBase, yBase, 1);
    yPred = polyval(p, t);

    residuo = tempSuav - yPred;

    residuoBase = residuo(idxEst:idxBaseFin);
    sigmaBase = std(residuoBase, 'omitnan');

    if ~isfinite(sigmaBase) || sigmaBase <= 0
        sigmaBase = 1;
    end

    umbralResiduo = max(3*sigmaBase, 3.0);

    cond = residuo > umbralResiduo & pendiente_C_h > 0.5*umbralLento_C_h;

    N = max(5, round(0.01*n));
    N = min(N, max(5, floor(n/10)));

    idxOut = buscar_condicion_sostenida(cond, idxBaseFin, N);
end

function idxOut = detectar_subida_brusca_por_curvatura(t, tempSuav, pendiente_C_h, idxGri)

    idxOut = NaN;

    n = numel(t);

    if idxGri >= n - 10
        return
    end

    d2 = gradient(pendiente_C_h, t);

    rango = idxGri:n;
    d2r = d2(rango);
    d2r(~isfinite(d2r)) = 0;

    if isempty(d2r)
        return
    end

    [~, iMax] = max(d2r);

    idxCandidato = rango(iMax);

    idxMin = idxGri + round(0.05*n);

    if idxCandidato < idxMin
        idxCandidato = idxMin;
    end

    idxCandidato = min(idxCandidato, n);

    if pendiente_C_h(idxCandidato) > 0
        idxOut = idxCandidato;
    end
end

function idx = buscar_indice_por_tiempo(t, tBuscado)

    if tBuscado <= t(1)
        idx = 1;
        return
    end

    if tBuscado >= t(end)
        idx = numel(t);
        return
    end

    idx = find(t >= tBuscado, 1, 'first');

    if isempty(idx)
        idx = numel(t);
    end
end

function idxPlot = obtener_indices_grafica(n, maxPuntos)

    if n <= maxPuntos
        idxPlot = 1:n;
    else
        paso = ceil(n / maxPuntos);
        idxPlot = 1:paso:n;

        if idxPlot(end) ~= n
            idxPlot = [idxPlot n];
        end
    end
end

function y = limitar_valor(x, xmin, xmax)

    y = max(xmin, min(x, xmax));
end

function col = detectar_columna_lista(vars, posibles)

    col = '';

    for k = 1:numel(posibles)
        idx = strcmpi(vars, posibles{k});

        if any(idx)
            col = vars{find(idx,1,'first')};
            return
        end
    end

    varsNorm = normalizar_nombres(vars);

    for k = 1:numel(posibles)
        pNorm = normalizar_nombre(posibles{k});
        idx = strcmpi(varsNorm, pNorm);

        if any(idx)
            col = vars{find(idx,1,'first')};
            return
        end
    end

    for k = 1:numel(posibles)

        pNorm = normalizar_nombre(posibles{k});

        for j = 1:numel(vars)
            if contains(varsNorm{j}, pNorm) || contains(pNorm, varsNorm{j})
                col = vars{j};
                return
            end
        end
    end
end

function out = normalizar_nombres(vars)

    out = cell(size(vars));

    for k = 1:numel(vars)
        out{k} = normalizar_nombre(vars{k});
    end
end

function s = normalizar_nombre(s)

    s = lower(s);
    s = erase(s, '_');
    s = erase(s, '-');
    s = erase(s, ' ');
    s = erase(s, '(');
    s = erase(s, ')');
    s = erase(s, '[');
    s = erase(s, ']');
    s = erase(s, '/');
    s = erase(s, '\');
end