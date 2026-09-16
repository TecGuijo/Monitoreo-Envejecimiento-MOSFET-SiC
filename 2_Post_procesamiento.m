clc
clear
clearvars
close all

% =========================================================
%  CONFIGURACION
% =========================================================
RTHjc = 0.60;       % C/W

calcBaseName = 'TDUT_TJ_RDSON';

maxBytesPerFile = 10 * 1024 * 1024;

% Limites de graficas principales
yLimTemp = [0 450];
yLimVDS  = [-20 20];
yLimID   = [-5 20];      % ID continuo en A
yLimVGS  = [-15 25];     % VGS en V

% Limites para capturas rapidas en mA
yLimIG_mA    = [-200 300];   % IG rapido en mA
yLimIDrap_mA = [-5 300];     % ID rapido en mA

% Parametros para RDS(on)
umbralID_RDSon  = 0.10;   % A
umbralVDS_RDSon = 5.00;   % V

% Maximo de puntos para graficas finales excepto TDUT/Tj
maxPlotPts = 200000;

% =========================================================
%  SELECCION DE CARPETA ORIGINAL
% =========================================================
baseFolder = uigetdir(pwd, 'Selecciona la carpeta general de la prueba');

if isequal(baseFolder,0)
    disp('No se selecciono carpeta.');
    return
end

% =========================================================
%  CREAR CARPETA NUEVA PARA RESULTADOS DEL POSTPROCESO
% =========================================================
outputFolder = fullfile(baseFolder, ...
    ['POSTPROCESO_' datestr(now,'yyyy_mm_dd_HH_MM_SS')]);

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

fprintf('\n====================================================\n');
fprintf('POSTPROCESO MAESTRO\n');
fprintf('Carpeta original: %s\n', baseFolder);
fprintf('Carpeta salida  : %s\n', outputFolder);
fprintf('RTHjc usado     : %.6f C/W\n', RTHjc);
fprintf('====================================================\n\n');

% =========================================================
%  BUSCAR Y LEER TEMPERATURAS
% =========================================================
fprintf('Buscando archivos de temperatura...\n');

archivosTemp = buscar_archivos_flexibles(baseFolder, ...
    {'TEMPERATURAS', 'TEMP', 'TEMPERATURA', 'TEMPS'});

if isempty(archivosTemp)
    error('No se encontraron archivos de temperatura.');
end

fprintf('Archivos de temperatura encontrados: %d\n', numel(archivosTemp));

TtempAll = leer_csvs_lista(archivosTemp);

if isempty(TtempAll) || height(TtempAll) < 2
    error('No se encontraron datos suficientes de temperatura.');
end

colTimeTemp = detectar_columna(TtempAll, ...
    {'Tiempo_s','TiempoGlobal_s','Time_s','t_s','Tiempo'});

colDUT = detectar_columna(TtempAll, ...
    {'TEMP_DUT_C','TDUT_C','DUT_C','TempDUT_C','TemperaturaDUT_C','T_DUT_C'});

colAMB = detectar_columna(TtempAll, ...
    {'TEMP_AMB_C','TAMB_C','AMB_C','TempAMB_C','TemperaturaAMB_C','T_AMB_C'});

colEXT = detectar_columna(TtempAll, ...
    {'TEMP_EXTRA_C','TEXTRA_C','EXTRA_C','TempEXTRA_C','TemperaturaEXTRA_C','T_EXTRA_C'});

if isempty(colTimeTemp)
    error('No se encontro columna de tiempo en archivos de temperatura.');
end

if isempty(colDUT)
    error('No se encontro columna de temperatura DUT.');
end

TtempAll = TtempAll(isfinite(TtempAll.(colTimeTemp)), :);
TtempAll = sortrows(TtempAll, colTimeTemp);

if ~isempty(TtempAll)
    idxMono = [true; diff(TtempAll.(colTimeTemp)) > 0];
    TtempAll = TtempAll(idxMono,:);
end

idxDUT = isfinite(TtempAll.(colTimeTemp)) & isfinite(TtempAll.(colDUT));

tTemp = TtempAll.(colTimeTemp)(idxDUT);
yTemp = TtempAll.(colDUT)(idxDUT);

[tTemp, idxSort] = sort(tTemp);
yTemp = yTemp(idxSort);

[tTemp, idxU] = unique(tTemp, 'stable');
yTemp = yTemp(idxU);

if numel(tTemp) < 2
    error('No hay suficientes puntos validos de temperatura DUT para interpolar.');
end

% =========================================================
%  GUARDAR TEMPERATURA COMPLETA DE CARCASA / DUT
% =========================================================
fprintf('\nGuardando archivo completo de temperatura de carcasa...\n');

tCarcasa = tTemp(:);
Tcarcasa_C = yTemp(:);

% Llevar tiempo desde 0 s
tCarcasa = tCarcasa - tCarcasa(1);

TcarcasaCompleta = table(tCarcasa, Tcarcasa_C, ...
    'VariableNames', {'Tiempo_s','TEMP_CARCASA_C'});

archivoTempCarcasa = fullfile(outputFolder, 'TEMP_CARCASA_COMPLETA.csv');

writetable(TcarcasaCompleta, archivoTempCarcasa);

fprintf('Archivo guardado: %s\n', archivoTempCarcasa);

% =========================================================
%  BUSCAR ARCHIVOS VDS/ID
% =========================================================
fprintf('\nBuscando archivos de VDS/ID...\n');

archivosVDSID = buscar_archivos_flexibles(baseFolder, ...
    {'VDS_ID', 'VDSID', 'VDS_ID_CONT', 'VDSID_CONTINUO'});

if isempty(archivosVDSID)
    error('No se encontraron archivos de VDS/ID.');
end

fprintf('Archivos VDS/ID encontrados: %d\n', numel(archivosVDSID));

% =========================================================
%  ELIMINAR CALCULOS PREVIOS SI EXISTEN EN CARPETA DE SALIDA
% =========================================================
archivosCalcPrevios = dir(fullfile(outputFolder, sprintf('%s_PARTE_*.csv', calcBaseName)));

if ~isempty(archivosCalcPrevios)
    resp = input('Ya existen CSV de calculo en la carpeta de salida. ¿Sobrescribirlos? (s/n): ','s');

    if strcmpi(resp,'s')
        for k = 1:numel(archivosCalcPrevios)
            try
                delete(fullfile(outputFolder, archivosCalcPrevios(k).name));
            catch
            end
        end
    else
        error('Postproceso cancelado para no sobrescribir resultados.');
    end
end

calcPart = 1;
calcCurrentFile = fullfile(outputFolder, sprintf('%s_PARTE_%03d.csv', calcBaseName, calcPart));
crear_csv_calc(calcCurrentFile);

% =========================================================
%  BUFFERS PARA GRAFICAS
% =========================================================
plotBuf = struct();

% VDS e ID se guardan completos y se deciman solo al final
plotBuf.tVDS = [];
plotBuf.vds  = [];

plotBuf.tID = [];
plotBuf.id  = [];

% TDUT y Tj se guardan completos y NO se deciman en la grafica final
plotBuf.tTDUT = [];
plotBuf.tdut  = [];

plotBuf.tTJ = [];
plotBuf.tj  = [];

% RDS(on) se mantiene con decimacion progresiva
plotBuf.rdson_t = [];
plotBuf.rdson   = [];

totalRowsProcessed = 0;
totalRowsCalc = 0;

% =========================================================
%  PROCESAR VDS/ID POR PARTES
% =========================================================
for k = 1:numel(archivosVDSID)

    nombre = archivosVDSID(k).fullpath;
    fprintf('Procesando VDS/ID: %s ...\n', archivosVDSID(k).name);

    try
        Tv = readtable(nombre);
    catch ME
        warning('No se pudo leer %s: %s', archivosVDSID(k).name, ME.message);
        continue
    end

    if isempty(Tv) || height(Tv) < 1
        clear Tv
        continue
    end

    colTime = detectar_columna(Tv, ...
        {'TiempoGlobal_s','Tiempo_s','Time_s','t_s','Tiempo'});

    colVDS = detectar_columna(Tv, ...
        {'VDS_V','Vds_V','VDS','V_DS_V','CH1_V','CH2_V'});

    colID = detectar_columna(Tv, ...
        {'ID_A','Id_A','ID','I_D_A','Corriente_A','CH3_A','CH4_A'});

    if isempty(colTime) || isempty(colVDS) || isempty(colID)
        warning('Archivo ignorado por columnas faltantes: %s', archivosVDSID(k).name);
        fprintf('Columnas encontradas:\n');
        disp(Tv.Properties.VariableNames');
        clear Tv
        continue
    end

    Tv = Tv(isfinite(Tv.(colTime)), :);

    if isempty(Tv)
        clear Tv
        continue
    end

    Tv = sortrows(Tv, colTime);

    idxMono = [true; diff(Tv.(colTime)) > 0];
    Tv = Tv(idxMono, :);

    tMaster = Tv.(colTime)(:);
    VDS     = Tv.(colVDS)(:);
    ID      = Tv.(colID)(:);

    TDUT_interp = interp1(tTemp, yTemp, tMaster, 'linear', NaN);

    Pd = VDS .* ID;
    Tj = TDUT_interp + Pd .* RTHjc;

    RDSon = nan(size(VDS));

    idxR = isfinite(VDS) & isfinite(ID) & isfinite(TDUT_interp) & ...
           abs(ID) >= umbralID_RDSon & ...
           abs(VDS) <= umbralVDS_RDSon;

    RDSon(idxR) = VDS(idxR) ./ ID(idxR);

    Tcalc = table(tMaster, TDUT_interp, VDS, ID, Pd, Tj, RDSon, double(idxR), ...
        'VariableNames', {'Tiempo_s','TDUT_C','VDS_V','ID_A','Pd_W','Tj_C','RDSon_Ohm','MascaraRDSon'});

    idxGuardar = isfinite(Tcalc.Tiempo_s) & isfinite(Tcalc.TDUT_C);
    Tcalc = Tcalc(idxGuardar, :);

    [calcCurrentFile, calcPart] = append_calc_rotativo( ...
        Tcalc, outputFolder, calcBaseName, calcCurrentFile, calcPart, maxBytesPerFile);

    % VDS e ID completos
    [plotBuf.tVDS, plotBuf.vds] = append_plot_sin_decimar(plotBuf.tVDS, plotBuf.vds, tMaster, VDS);
    [plotBuf.tID,  plotBuf.id ] = append_plot_sin_decimar(plotBuf.tID,  plotBuf.id,  tMaster, ID);

    % =====================================================
    % TDUT y Tj COMPLETOS, SIN DECIMAR
    % =====================================================
    [plotBuf.tTDUT, plotBuf.tdut] = append_plot_sin_decimar(plotBuf.tTDUT, plotBuf.tdut, ...
        Tcalc.Tiempo_s, Tcalc.TDUT_C);

    [plotBuf.tTJ, plotBuf.tj] = append_plot_sin_decimar(plotBuf.tTJ, plotBuf.tj, ...
        Tcalc.Tiempo_s, Tcalc.Tj_C);

    % RDS(on) decimado para no saturar memoria/grafica
    idxRplot = Tcalc.MascaraRDSon == 1 & isfinite(Tcalc.RDSon_Ohm);

    [plotBuf.rdson_t, plotBuf.rdson] = append_plot_decimado(plotBuf.rdson_t, plotBuf.rdson, ...
        Tcalc.Tiempo_s(idxRplot), Tcalc.RDSon_Ohm(idxRplot), maxPlotPts);

    totalRowsProcessed = totalRowsProcessed + height(Tv);
    totalRowsCalc      = totalRowsCalc + height(Tcalc);

    clear Tv tMaster VDS ID TDUT_interp Pd Tj RDSon idxR Tcalc
end

fprintf('\nFilas VDS/ID procesadas: %d\n', totalRowsProcessed);
fprintf('Filas calculadas guardadas: %d\n', totalRowsCalc);

% =========================================================
%  GUARDAR RESUMEN EN CARPETA DE SALIDA
% =========================================================
resumenFile = fullfile(outputFolder, 'RESUMEN_POSTPROCESO.txt');

fid = fopen(resumenFile, 'w');

if fid < 0
    warning('No se pudo crear el archivo de resumen.');
else
    fprintf(fid, 'POSTPROCESO MAESTRO CON ID RAPIDO\n');
    fprintf(fid, 'Fecha postproceso: %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'Carpeta original de datos: %s\n', baseFolder);
    fprintf(fid, 'Carpeta de resultados: %s\n', outputFolder);
    fprintf(fid, 'RTHjc: %.9f C/W\n', RTHjc);
    fprintf(fid, 'umbralID_RDSon: %.9f A\n', umbralID_RDSon);
    fprintf(fid, 'umbralVDS_RDSon: %.9f V\n', umbralVDS_RDSon);
    fprintf(fid, 'Filas VDS/ID procesadas: %d\n', totalRowsProcessed);
    fprintf(fid, 'Filas calculadas guardadas: %d\n', totalRowsCalc);
    fprintf(fid, 'Archivo temperatura carcasa completa: %s\n', archivoTempCarcasa);
    fprintf(fid, 'Grafica TDUT/Tj: sin decimacion\n');
    fclose(fid);
end

% =========================================================
%  GRAFICAS FINALES
% =========================================================
fprintf('\nGenerando graficas finales...\n');

% ---------------------------------------------------------
% Temperaturas
% ---------------------------------------------------------
figure('Name','Temperaturas finales','NumberTitle','off');
hold on

[tD, yD] = decimar_para_plot(TtempAll.(colTimeTemp), TtempAll.(colDUT), maxPlotPts);

if ~isempty(tD)
    tD = tD - tD(1);
end

plot(tD, yD, 'LineWidth',1.1, 'DisplayName','TEMP DUT');

if ~isempty(colAMB)
    [tA, yA] = decimar_para_plot(TtempAll.(colTimeTemp), TtempAll.(colAMB), maxPlotPts);

    if ~isempty(tA)
        tA = tA - tA(1);
    end

    plot(tA, yA, 'LineWidth',1.1, 'DisplayName','TEMP AMB');
end

if ~isempty(colEXT)
    [tE, yE] = decimar_para_plot(TtempAll.(colTimeTemp), TtempAll.(colEXT), maxPlotPts);

    if ~isempty(tE)
        tE = tE - tE(1);
    end

    plot(tE, yE, 'LineWidth',1.1, 'DisplayName','TEMP EXTRA');
end

grid on
xlabel('Tiempo (s)');
ylabel('Temperatura (°C)');
title('Temperaturas finales desde 0 s');
legend('Location','best');
ylim(yLimTemp);
hold off

% ---------------------------------------------------------
% VDS desde t = 0 s
% ---------------------------------------------------------
if ~isempty(plotBuf.tVDS)

    [tVDS_plot, vds_plot] = preparar_plot_desde_cero(plotBuf.tVDS, plotBuf.vds, maxPlotPts);

    figure('Name','VDS global desde 0 s','NumberTitle','off');
    plot(tVDS_plot, vds_plot, 'LineWidth',1.0);
    grid on
    xlabel('Tiempo (s)');
    ylabel('VDS (V)');
    title('VDS global desde 0 s');
    ylim(yLimVDS);

else
    warning('No hay datos para graficar VDS.');
end

% ---------------------------------------------------------
% ID continuo desde t = 0 s
% ---------------------------------------------------------
if ~isempty(plotBuf.tID)

    [tID_plot, id_plot] = preparar_plot_desde_cero(plotBuf.tID, plotBuf.id, maxPlotPts);

    figure('Name','ID global desde 0 s','NumberTitle','off');
    plot(tID_plot, id_plot, 'LineWidth',1.0);
    grid on
    xlabel('Tiempo (s)');
    ylabel('ID continuo (A)');
    title('ID global continuo desde 0 s');
    ylim(yLimID);

else
    warning('No hay datos para graficar ID.');
end

% ---------------------------------------------------------
% TDUT y Tj SIN DECIMACION
% ---------------------------------------------------------
if ~isempty(plotBuf.tTDUT) || ~isempty(plotBuf.tTJ)

    figure('Name','TDUT y Tj sin decimacion','NumberTitle','off');
    hold on

    if ~isempty(plotBuf.tTDUT)
        [tTDUT_plot, tdut_plot] = preparar_plot_desde_cero_sin_decimar(plotBuf.tTDUT, plotBuf.tdut);
        plot(tTDUT_plot, tdut_plot, 'LineWidth',1.1, 'DisplayName','TDUT');
    end

    if ~isempty(plotBuf.tTJ)
        [tTJ_plot, tj_plot] = preparar_plot_desde_cero_sin_decimar(plotBuf.tTJ, plotBuf.tj);
        plot(tTJ_plot, tj_plot, 'LineWidth',1.1, 'DisplayName','Tj');
    end

    grid on
    xlabel('Tiempo (s)');
    ylabel('Temperatura (°C)');
    title('TDUT y Tj desde 0 s sin decimacion');
    legend('Location','best');
    hold off

else
    warning('No hay datos para graficar TDUT/Tj.');
end

% ---------------------------------------------------------
% RDS(on)
% ---------------------------------------------------------
if ~isempty(plotBuf.rdson_t)

    [tRDS_plot, rdson_plot] = preparar_plot_desde_cero(plotBuf.rdson_t, plotBuf.rdson, maxPlotPts);

    figure('Name','RDS(on) decimado','NumberTitle','off');
    plot(tRDS_plot, rdson_plot, 'LineWidth',1.0);
    grid on
    xlabel('Tiempo (s)');
    ylabel('RDS(on) (\Omega)');
    title('RDS(on) desde 0 s');

else
    warning('No hay datos validos para graficar RDS(on).');
end

% ---------------------------------------------------------
% SOLO PRIMER VGSON Y PRIMER VGSOFF
% Se grafica VGS + ID rapido combinado.
% Se grafica IG rapido aparte.
% No se grafica ID rapido solo.
% No se grafica VGS/ID separados.
% ---------------------------------------------------------
graficar_solo_primer_vgson_vgsoff(baseFolder, yLimVGS, yLimIG_mA, yLimIDrap_mA);

fprintf('\n====================================================\n');
fprintf('POSTPROCESO FINALIZADO\n');
fprintf('Carpeta original: %s\n', baseFolder);
fprintf('Archivos calculados en: %s\n', outputFolder);
fprintf('Resumen: %s\n', resumenFile);
fprintf('Temperatura carcasa completa: %s\n', archivoTempCarcasa);
fprintf('====================================================\n');

% =========================================================
%  FUNCIONES LOCALES
% =========================================================

function archivosOut = buscar_archivos_flexibles(baseFolder, patrones)

    archivosOut = struct('name', {}, 'folder', {}, 'fullpath', {}, 'bytes', {});

    carpetasBuscar = {baseFolder};

    subdirs = dir(baseFolder);

    for i = 1:numel(subdirs)
        if subdirs(i).isdir
            nombre = subdirs(i).name;

            if ~strcmp(nombre,'.') && ~strcmp(nombre,'..')
                carpetasBuscar{end+1} = fullfile(baseFolder, nombre); %#ok<AGROW>
            end
        end
    end

    for c = 1:numel(carpetasBuscar)

        carpeta = carpetasBuscar{c};

        for p = 1:numel(patrones)

            patron = patrones{p};

            candidatos = [
                dir(fullfile(carpeta, sprintf('%s*.csv', patron)));
                dir(fullfile(carpeta, sprintf('*%s*.csv', patron)))
            ];

            for k = 1:numel(candidatos)

                if candidatos(k).isdir
                    continue
                end

                fullp = fullfile(candidatos(k).folder, candidatos(k).name);

                yaExiste = false;

                for q = 1:numel(archivosOut)
                    if strcmpi(archivosOut(q).fullpath, fullp)
                        yaExiste = true;
                        break
                    end
                end

                if ~yaExiste
                    nuevo.name = candidatos(k).name;
                    nuevo.folder = candidatos(k).folder;
                    nuevo.fullpath = fullp;
                    nuevo.bytes = candidatos(k).bytes;
                    archivosOut(end+1) = nuevo; %#ok<AGROW>
                end
            end
        end
    end

    if isempty(archivosOut)
        return
    end

    nombres = {archivosOut.name}';
    nums = nan(numel(nombres),1);

    for k = 1:numel(nombres)

        tok = regexp(nombres{k}, 'PARTE[_\- ]*(\d+)', 'tokens', 'once');

        if isempty(tok)
            tok = regexp(nombres{k}, '(\d+)', 'tokens');

            if ~isempty(tok)
                nums(k) = str2double(tok{end}{1});
            else
                nums(k) = inf;
            end
        else
            nums(k) = str2double(tok{1});
        end
    end

    [~, idx] = sort(nums);
    archivosOut = archivosOut(idx);
end

function T = leer_csvs_lista(archivos)

    T = table();

    for k = 1:numel(archivos)

        try
            Tk = readtable(archivos(k).fullpath);

            if ~isempty(Tk)
                T = [T; Tk]; %#ok<AGROW>
            end

        catch ME
            warning('No se pudo leer %s: %s', archivos(k).name, ME.message);
        end
    end
end

function col = detectar_columna(T, posibles)

    col = '';
    vars = T.Properties.VariableNames;

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

function crear_csv_calc(nombreCSV)

    fid = fopen(nombreCSV,'w');

    if fid < 0
        error('No se pudo crear archivo: %s', nombreCSV);
    end

    fprintf(fid, 'Tiempo_s,TDUT_C,VDS_V,ID_A,Pd_W,Tj_C,RDSon_Ohm,MascaraRDSon\n');
    fclose(fid);
end

function [calcCurrentFile, calcPart] = append_calc_rotativo(Tcalc, outputFolder, calcBaseName, calcCurrentFile, calcPart, maxBytesPerFile)

    if isempty(Tcalc) || height(Tcalc) == 0
        return
    end

    bytesPorFilaAprox = 120;
    n = height(Tcalc);
    idxIni = 1;

    while idxIni <= n

        bytesActual = get_file_bytes(calcCurrentFile);

        if bytesActual >= maxBytesPerFile
            calcPart = calcPart + 1;
            calcCurrentFile = fullfile(outputFolder, sprintf('%s_PARTE_%03d.csv', calcBaseName, calcPart));
            crear_csv_calc(calcCurrentFile);
            bytesActual = get_file_bytes(calcCurrentFile);
        end

        bytesDisponibles = max(maxBytesPerFile - bytesActual, 1e6);
        filasChunk = max(1000, floor(bytesDisponibles / bytesPorFilaAprox));

        idxFin = min(n, idxIni + filasChunk - 1);
        Tk = Tcalc(idxIni:idxFin, :);

        fid = fopen(calcCurrentFile, 'a');

        if fid < 0
            error('No se pudo abrir archivo de calculo: %s', calcCurrentFile);
        end

        A = [Tk.Tiempo_s, Tk.TDUT_C, Tk.VDS_V, Tk.ID_A, Tk.Pd_W, Tk.Tj_C, Tk.RDSon_Ohm, Tk.MascaraRDSon];

        fprintf(fid, '%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%d\n', A.');

        fclose(fid);

        idxIni = idxFin + 1;
    end
end

function n = get_file_bytes(fname)

    n = 0;

    try
        if isfile(fname)
            d = dir(fname);
            n = d.bytes;
        end
    catch
        n = 0;
    end
end

function [tOut, yOut] = decimar_para_plot(t, y, maxPts)

    t = t(:);
    y = y(:);

    idx = isfinite(t) & isfinite(y);

    t = t(idx);
    y = y(idx);

    n = numel(t);

    if n <= maxPts
        tOut = t;
        yOut = y;
        return
    end

    paso = ceil(n / maxPts);
    idxKeep = 1:paso:n;

    tOut = t(idxKeep);
    yOut = y(idxKeep);
end

function [tAccum, yAccum] = append_plot_decimado(tAccum, yAccum, tNew, yNew, maxPts)

    if isempty(tNew) || isempty(yNew)
        return
    end

    tNew = tNew(:);
    yNew = yNew(:);

    idx = isfinite(tNew) & isfinite(yNew);

    tNew = tNew(idx);
    yNew = yNew(idx);

    if isempty(tNew)
        return
    end

    tAccum = [tAccum(:); tNew(:)]; %#ok<AGROW>
    yAccum = [yAccum(:); yNew(:)]; %#ok<AGROW>

    if numel(tAccum) > maxPts
        paso = ceil(numel(tAccum) / maxPts);
        idxKeep = 1:paso:numel(tAccum);

        tAccum = tAccum(idxKeep);
        yAccum = yAccum(idxKeep);
    end
end

function [tAccum, yAccum] = append_plot_sin_decimar(tAccum, yAccum, tNew, yNew)

    if isempty(tNew) || isempty(yNew)
        return
    end

    tNew = tNew(:);
    yNew = yNew(:);

    idx = isfinite(tNew) & isfinite(yNew);

    tNew = tNew(idx);
    yNew = yNew(idx);

    if isempty(tNew)
        return
    end

    tAccum = [tAccum(:); tNew(:)]; %#ok<AGROW>
    yAccum = [yAccum(:); yNew(:)]; %#ok<AGROW>
end

function [tOut, yOut] = preparar_plot_desde_cero(t, y, maxPts)

    t = t(:);
    y = y(:);

    idx = isfinite(t) & isfinite(y);

    t = t(idx);
    y = y(idx);

    if isempty(t)
        tOut = [];
        yOut = [];
        return
    end

    [t, idxSort] = sort(t);
    y = y(idxSort);

    [t, idxU] = unique(t, 'stable');
    y = y(idxU);

    t = t - t(1);

    [tOut, yOut] = decimar_para_plot(t, y, maxPts);
end

function [tOut, yOut] = preparar_plot_desde_cero_sin_decimar(t, y)

    t = t(:);
    y = y(:);

    idx = isfinite(t) & isfinite(y);

    t = t(idx);
    y = y(idx);

    if isempty(t)
        tOut = [];
        yOut = [];
        return
    end

    [t, idxSort] = sort(t);
    y = y(idxSort);

    [t, idxU] = unique(t, 'stable');
    y = y(idxU);

    tOut = t - t(1);
    yOut = y;
end

function graficar_solo_primer_vgson_vgsoff(baseFolder, yLimVGS, yLimIG_mA, yLimIDrap_mA)

    fprintf('\nBuscando SOLO primer VGSON y primer VGSOFF con ID rapido...\n');

    archivos = dir(fullfile(baseFolder, '**', '*.csv'));

    if isempty(archivos)
        warning('No se encontraron CSV para buscar VGSON/VGSOFF.');
        return
    end

    nombresFull = strings(numel(archivos),1);

    for k = 1:numel(archivos)
        nombresFull(k) = lower(fullfile(archivos(k).folder, archivos(k).name));
    end

    [~, idxOrd] = sort(nombresFull);
    archivos = archivos(idxOrd);

    tOn = [];
    vgsOn = [];
    igOn = [];
    idOn = [];
    nameOn = '';

    tOff = [];
    vgsOff = [];
    igOff = [];
    idOff = [];
    nameOff = '';

    encontroON = false;
    encontroOFF = false;

    for k = 1:numel(archivos)

        if encontroON && encontroOFF
            break
        end

        nombreArchivo = archivos(k).name;
        nombreMayus = upper(nombreArchivo);
        nombreCompleto = fullfile(archivos(k).folder, archivos(k).name);

        pareceON  = contains(nombreMayus, 'VGSON')  || ...
                    contains(nombreMayus, 'VGS_ON') || ...
                    contains(nombreMayus, 'CAPTURA_ON') || ...
                    contains(nombreMayus, '_ON');

        pareceOFF = contains(nombreMayus, 'VGSOFF')  || ...
                    contains(nombreMayus, 'VGS_OFF') || ...
                    contains(nombreMayus, 'CAPTURA_OFF') || ...
                    contains(nombreMayus, '_OFF');

        if ~pareceON && ~pareceOFF
            continue
        end

        try
            T = readtable(nombreCompleto);
        catch ME
            warning('No se pudo leer %s: %s', nombreArchivo, ME.message);
            continue
        end

        if isempty(T) || height(T) < 2
            continue
        end

        colTime = detectar_columna_vgs(T, ...
            {'TiempoLocal_s','TiempoGlobal_s','Tiempo_s','Time_s','t_s','Tiempo','time','TIME'});

        colVGS = detectar_columna_vgs_tipo(T, ...
            {'VGSON_V','VGSOFF_V','VGS_ON_V','VGS_OFF_V','VGS_V','Vgs_V','VGS','V_GS_V','VGATE_V','Vgate_V','CH2_V'}, ...
            'vgs');

        colIG = detectar_columna_vgs_tipo(T, ...
            {'IGON_A','IGOFF_A','IG_ON_A','IG_OFF_A','IG_A','Ig_A','IG','I_G_A','GateCurrent_A','Igate_A','CH3_A'}, ...
            'ig');

        colID = detectar_columna_vgs_tipo(T, ...
            {'ID_A','Id_A','ID','I_D_A','DrainCurrent_A','Idrain_A','ID_RAPIDO_A','IDrapido_A','CH4_A'}, ...
            'id');

        if isempty(colTime)
            t = (0:height(T)-1).';
            colTime = 'IndiceMuestra';
        else
            t = T.(colTime)(:);
        end

        if isempty(colVGS)
            continue
        end

        vgs = T.(colVGS)(:);

        if isempty(colIG)
            ig = nan(size(vgs));
        else
            ig = T.(colIG)(:);
        end

        if isempty(colID)
            id = nan(size(vgs));
        else
            id = T.(colID)(:);
        end

        idx = isfinite(t) & isfinite(vgs);

        if pareceON && ~encontroON
            tOn = t(idx);
            vgsOn = vgs(idx);
            igOn = ig(idx);
            idOn = id(idx);
            nameOn = nombreArchivo;

            if numel(tOn) >= 2
                encontroON = true;

                fprintf('\nPrimer VGSON encontrado:\n');
                fprintf('  Archivo: %s\n', nameOn);
                fprintf('  Tiempo : %s\n', colTime);
                fprintf('  VGS    : %s\n', colVGS);

                if isempty(colIG)
                    fprintf('  IG     : no encontrado\n');
                else
                    fprintf('  IG     : %s\n', colIG);
                end

                if isempty(colID)
                    fprintf('  ID     : no encontrado\n');
                else
                    fprintf('  ID     : %s\n', colID);
                end
            end
        end

        if pareceOFF && ~encontroOFF
            tOff = t(idx);
            vgsOff = vgs(idx);
            igOff = ig(idx);
            idOff = id(idx);
            nameOff = nombreArchivo;

            if numel(tOff) >= 2
                encontroOFF = true;

                fprintf('\nPrimer VGSOFF encontrado:\n');
                fprintf('  Archivo: %s\n', nameOff);
                fprintf('  Tiempo : %s\n', colTime);
                fprintf('  VGS    : %s\n', colVGS);

                if isempty(colIG)
                    fprintf('  IG     : no encontrado\n');
                else
                    fprintf('  IG     : %s\n', colIG);
                end

                if isempty(colID)
                    fprintf('  ID     : no encontrado\n');
                else
                    fprintf('  ID     : %s\n', colID);
                end
            end
        end
    end

    if ~encontroON
        warning('No se encontro primer VGSON.');
    end

    if ~encontroOFF
        warning('No se encontro primer VGSOFF.');
    end

    if encontroON
        graficar_evento_vgs_ig_id(tOn, vgsOn, igOn, idOn, nameOn, ...
            'VGSON primero', yLimVGS, yLimIG_mA, yLimIDrap_mA);
    end

    if encontroOFF
        graficar_evento_vgs_ig_id(tOff, vgsOff, igOff, idOff, nameOff, ...
            'VGSOFF primero', yLimVGS, yLimIG_mA, yLimIDrap_mA);
    end
end

function col = detectar_columna_vgs(T, posibles)

    col = '';
    vars = T.Properties.VariableNames;

    for k = 1:numel(posibles)

        idx = strcmpi(vars, posibles{k});

        if any(idx)
            col = vars{find(idx,1,'first')};
            return
        end
    end

    varsNorm = normalizar_nombres_vgs(vars);
    posiblesNorm = normalizar_nombres_vgs(posibles);

    for k = 1:numel(posiblesNorm)

        idx = strcmpi(varsNorm, posiblesNorm{k});

        if any(idx)
            col = vars{find(idx,1,'first')};
            return
        end
    end

    for i = 1:numel(varsNorm)
        if contains(varsNorm{i}, 'tiempo') || contains(varsNorm{i}, 'time')
            col = vars{i};
            return
        end
    end
end

function col = detectar_columna_vgs_tipo(T, posibles, tipo)

    col = '';
    vars = T.Properties.VariableNames;

    for k = 1:numel(posibles)

        idx = strcmpi(vars, posibles{k});

        if any(idx)
            col = vars{find(idx,1,'first')};
            return
        end
    end

    varsNorm = normalizar_nombres_vgs(vars);
    posiblesNorm = normalizar_nombres_vgs(posibles);

    for k = 1:numel(posiblesNorm)

        idx = strcmpi(varsNorm, posiblesNorm{k});

        if any(idx)
            col = vars{find(idx,1,'first')};
            return
        end
    end

    tipo = lower(tipo);

    switch tipo

        case 'vgs'
            for i = 1:numel(varsNorm)
                if contains(varsNorm{i}, 'vgs') || ...
                   contains(varsNorm{i}, 'vgate') || ...
                   contains(varsNorm{i}, 'gatevoltage') || ...
                   contains(varsNorm{i}, 'vgson') || ...
                   contains(varsNorm{i}, 'vgsoff') || ...
                   strcmp(varsNorm{i}, 'ch2v')
                    col = vars{i};
                    return
                end
            end

        case 'ig'
            for i = 1:numel(varsNorm)
                if contains(varsNorm{i}, 'ig') || ...
                   contains(varsNorm{i}, 'igate') || ...
                   contains(varsNorm{i}, 'gatecurrent') || ...
                   contains(varsNorm{i}, 'igon') || ...
                   contains(varsNorm{i}, 'igoff') || ...
                   strcmp(varsNorm{i}, 'ch3a')
                    col = vars{i};
                    return
                end
            end

        case 'id'
            for i = 1:numel(varsNorm)
                if strcmp(varsNorm{i}, 'ida') || ...
                   strcmp(varsNorm{i}, 'id') || ...
                   contains(varsNorm{i}, 'draincurrent') || ...
                   contains(varsNorm{i}, 'idrain') || ...
                   contains(varsNorm{i}, 'idrapido') || ...
                   strcmp(varsNorm{i}, 'ch4a')
                    col = vars{i};
                    return
                end
            end
    end
end

function out = normalizar_nombres_vgs(vars)

    out = cell(size(vars));

    for i = 1:numel(vars)
        s = lower(vars{i});
        s = erase(s, '_');
        s = erase(s, '-');
        s = erase(s, ' ');
        s = erase(s, '(');
        s = erase(s, ')');
        s = erase(s, '[');
        s = erase(s, ']');
        s = erase(s, '/');
        s = erase(s, '\');
        out{i} = s;
    end
end

function graficar_evento_vgs_ig_id(t, vgs, ig, id, nombreArchivo, tipoEvento, yLimVGS, yLimIG_mA, yLimIDrap_mA)

    t = t(:);
    vgs = vgs(:);
    ig = ig(:);
    id = id(:);

    idx = isfinite(t) & isfinite(vgs);

    t = t(idx);
    vgs = vgs(idx);
    ig = ig(idx);
    id = id(idx);

    if numel(t) < 2
        return
    end

    t_us = (t - t(1)) * 1e6;

    % Convertir corrientes rapidas de A a mA
    ig_mA = ig * 1e3;
    id_mA = id * 1e3;

    % =====================================================
    % Figura combinada VGS + ID rapido
    % Esta es la unica grafica donde aparece ID rapido.
    % =====================================================
    figure('Name',['Captura ' tipoEvento ' - VGS ID rapido'],'NumberTitle','off');

    yyaxis left
    plot(t_us, vgs, 'LineWidth',1.2, 'DisplayName','VGS');
    ylabel('VGS (V)');
    ylim(yLimVGS);
    grid on
    hold on

    yyaxis right
    hold on

    if any(isfinite(id_mA))
        plot(t_us, id_mA, 'LineWidth',1.2, 'DisplayName','ID rapido');
    end

    ylabel('ID rapido (mA)');
    ylim(yLimIDrap_mA);

    xlabel('Tiempo (\mus)');
    title(sprintf('%s: %s', tipoEvento, nombreArchivo), 'Interpreter','none');

    if any(isfinite(id_mA))
        legend('VGS','ID rapido','Location','best');
    else
        legend('VGS','Location','best');
    end

    % =====================================================
    % Figura extra SOLO IG rapido en mA
    % =====================================================
    if any(isfinite(ig_mA))
        figure('Name',['IG rapido ' tipoEvento],'NumberTitle','off');
        plot(t_us, ig_mA, 'LineWidth',1.2);
        grid on
        xlabel('Tiempo (\mus)');
        ylabel('IG rapido (mA)');
        title(sprintf('IG rapido %s: %s', tipoEvento, nombreArchivo), 'Interpreter','none');
        ylim(yLimIG_mA);
    end
end