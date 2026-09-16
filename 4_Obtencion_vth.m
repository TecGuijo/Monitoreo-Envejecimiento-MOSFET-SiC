clc;
clear;
close all;

% =========================================================
%  DETECCION AUTOMATICA DE Vth DINAMICO PARA ARCHIVOS
%  CAPTURA_ON_CICLO
%  SIN GRAFICAS, SOLO RESULTADO EN CSV
% =========================================================
%
% Columnas esperadas:
%   TiempoLocal_s, VGS_V, ID_A
%
% Salida:
%   RESUMEN_VTH_DINAMICO_CAPTURA_ON.csv
%
% Columnas principales:
%   Ciclo, Archivo, Vth_dinamico_V
% =========================================================

% =========================================================
%  CONFIGURACION DEL USUARIO
% =========================================================

VGS_base_limite = 0;

% Ventana de busqueda en microsegundos
t_busqueda_min_us = 0.712;
t_busqueda_max_us = 0.750;

% Suavizado
ventana_suavizado = 11;

% Deteccion del inicio del levantamiento
porcentaje_pendiente_inicio = 0.10;
N_consecutivos_inicio = 2;

% Nombre obligatorio dentro del archivo
% Se buscan archivos que contengan "CAPTURA_ON_CICLO"
textoArchivoObjetivo = 'captura_on_ciclo';

% Nombre de carpeta de salida
nombreCarpetaSalida = 'RESULTADOS_VTH_DINAMICO';

% Nombre del CSV final
nombreCSVResumen = 'RESUMEN_VTH_DINAMICO_CAPTURA_ON.csv';

% =========================================================
%  SELECCIONAR CARPETA
% =========================================================

rutaCarpeta = uigetdir(pwd, 'Selecciona la carpeta con los CSV CAPTURA_ON_CICLO');

if isequal(rutaCarpeta, 0)
    disp('No se selecciono ninguna carpeta.');
    return;
end

fprintf('Carpeta seleccionada:\n%s\n\n', rutaCarpeta);

% =========================================================
%  BUSCAR SOLO ARCHIVOS CAPTURA_ON_CICLO
% =========================================================

archivosTodos = dir(fullfile(rutaCarpeta, '*.csv'));

if isempty(archivosTodos)
    error('No se encontraron archivos CSV en la carpeta seleccionada.');
end

nombresTodos = {archivosTodos.name};

idxObjetivo = contains(lower(nombresTodos), textoArchivoObjetivo);

archivos = archivosTodos(idxObjetivo);

if isempty(archivos)
    error('No se encontraron archivos CSV que contengan CAPTURA_ON_CICLO en el nombre.');
end

% Ordenar por ciclo real detectado en el nombre
ciclosDetectados = zeros(numel(archivos), 1);

for i = 1:numel(archivos)
    ciclosDetectados(i) = extraer_ciclo_desde_nombre(archivos(i).name, i);
end

[~, idxOrden] = sort(ciclosDetectados);
archivos = archivos(idxOrden);

fprintf('Archivos CAPTURA_ON_CICLO encontrados: %d\n\n', numel(archivos));

% =========================================================
%  CREAR CARPETA DE SALIDA
% =========================================================

rutaSalida = fullfile(rutaCarpeta, nombreCarpetaSalida);

if ~exist(rutaSalida, 'dir')
    mkdir(rutaSalida);
end

archivoResumen = fullfile(rutaSalida, nombreCSVResumen);

% =========================================================
%  TABLA DE RESULTADOS
% =========================================================

resultados = table();

% =========================================================
%  PROCESAR ARCHIVOS
% =========================================================

for n = 1:numel(archivos)

    nombreArchivo = archivos(n).name;
    archivoActual = fullfile(rutaCarpeta, nombreArchivo);

    fprintf('Procesando %d/%d: %s\n', n, numel(archivos), nombreArchivo);

    Ciclo = extraer_ciclo_desde_nombre(nombreArchivo, n);
    Estado = "OK";
    Mensaje = "";

    try
        % =========================================================
        %  LEER CSV
        % =========================================================

        T = readtable(archivoActual);

        columnasNecesarias = {'TiempoLocal_s', 'VGS_V', 'ID_A'};

        for k = 1:numel(columnasNecesarias)
            if ~ismember(columnasNecesarias{k}, T.Properties.VariableNames)
                error('El archivo no contiene la columna necesaria: %s', columnasNecesarias{k});
            end
        end

        % =========================================================
        %  EXTRAER VARIABLES
        % =========================================================

        t   = T.TiempoLocal_s;
        VGS = T.VGS_V;
        ID  = T.ID_A;

        t   = t(:);
        VGS = VGS(:);
        ID  = ID(:);

        % =========================================================
        %  LIMPIAR DATOS NO VALIDOS
        % =========================================================

        idxValidos = isfinite(t) & isfinite(VGS) & isfinite(ID);

        t   = t(idxValidos);
        VGS = VGS(idxValidos);
        ID  = ID(idxValidos);

        if numel(t) < 10
            error('El archivo tiene muy pocos datos validos.');
        end

        % =========================================================
        %  ORDENAR POR TIEMPO
        % =========================================================

        [t, idxOrdenTiempo] = sort(t);
        VGS = VGS(idxOrdenTiempo);
        ID  = ID(idxOrdenTiempo);

        t_us = t * 1e6;

        % =========================================================
        %  ESTIMAR CORRIENTE BASE
        % =========================================================

        idxBase = VGS < VGS_base_limite;

        if sum(idxBase) < 5
            Nbase = max(5, round(0.10 * numel(ID)));

            idxBase = false(size(ID));
            idxBase(1:Nbase) = true;
        end

        ID_base_A = median(ID(idxBase), 'omitnan');

        % =========================================================
        %  CORREGIR OFFSET DE ID
        % =========================================================

        ID_corr_A = ID - ID_base_A;

        % =========================================================
        %  SUAVIZAR ID
        % =========================================================

        ID_corr_s_A = movmean(ID_corr_A, ventana_suavizado, 'omitnan');

        % =========================================================
        %  VENTANA DE BUSQUEDA
        % =========================================================

        idxVentanaBusqueda = t_us >= t_busqueda_min_us & ...
                             t_us <= t_busqueda_max_us;

        if sum(idxVentanaBusqueda) < 5
            error('La ventana de busqueda tiene muy pocos puntos.');
        end

        idxVentana = find(idxVentanaBusqueda);

        ID_win_A = ID_corr_s_A(idxVentana);

        % =========================================================
        %  BUSCAR VALLE / MINIMO LOCAL DE ID
        % =========================================================

        [ID_min_A, idxRelValle] = min(ID_win_A);
        idxValle = idxVentana(idxRelValle);

        tValle_s = t(idxValle);
        VGS_valle_V = VGS(idxValle);
        ID_valle_corr_A = ID_corr_A(idxValle);
        ID_valle_original_A = ID(idxValle);

        % =========================================================
        %  CALCULAR dID/dt
        % =========================================================

        dIDdt_A_por_us = gradient(ID_corr_s_A) ./ gradient(t_us);
        dIDdt_A_por_us(~isfinite(dIDdt_A_por_us)) = NaN;

        dIDdt_s_A_por_us = movmean(dIDdt_A_por_us, ventana_suavizado, 'omitnan');

        % =========================================================
        %  BUSCAR INICIO DEL LEVANTAMIENTO DESPUES DEL VALLE
        % =========================================================

        idxDespuesValle = idxVentana(idxVentana >= idxValle);

        if numel(idxDespuesValle) < 3
            error('Hay muy pocos puntos despues del valle dentro de la ventana.');
        end

        dIDdt_post = dIDdt_s_A_por_us(idxDespuesValle);
        dIDdt_post = dIDdt_post(isfinite(dIDdt_post));

        if isempty(dIDdt_post)
            error('No hay datos validos de dID/dt despues del valle.');
        end

        dIDdt_max_A_por_us = max(dIDdt_post, [], 'omitnan');

        if dIDdt_max_A_por_us <= 0 || ~isfinite(dIDdt_max_A_por_us)
            error('No se encontro pendiente positiva despues del valle.');
        end

        umbral_dIDdt_A_por_us = porcentaje_pendiente_inicio * dIDdt_max_A_por_us;

        idxInicioPendiente = [];
        contador = 0;

        for k = 1:numel(idxDespuesValle)

            idxActual = idxDespuesValle(k);

            condicionPendiente = dIDdt_s_A_por_us(idxActual) > umbral_dIDdt_A_por_us;
            condicionSubida    = ID_corr_s_A(idxActual) > ID_min_A;

            if condicionPendiente && condicionSubida
                contador = contador + 1;
            else
                contador = 0;
            end

            if contador >= N_consecutivos_inicio
                idxInicioPendiente = idxDespuesValle(k - N_consecutivos_inicio + 1);
                break;
            end
        end

        if isempty(idxInicioPendiente)
            error('No se encontro el inicio del levantamiento de ID.');
        end

        % =========================================================
        %  RESULTADO Vth DINAMICO
        % =========================================================

        Vth_dyn_V = VGS(idxInicioPendiente);
        tVth_s = t(idxInicioPendiente);

        ID_punto_corr_A = ID_corr_A(idxInicioPendiente);
        ID_punto_original_A = ID(idxInicioPendiente);
        dIDdt_punto_A_por_us = dIDdt_s_A_por_us(idxInicioPendiente);

        [~, idxRelPicoID] = max(ID_win_A);
        idxPico = idxVentana(idxRelPicoID);

        VGS_pico_V = VGS(idxPico);
        tPico_s = t(idxPico);
        ID_pico_corr_A = ID_corr_A(idxPico);
        ID_pico_original_A = ID(idxPico);

    catch ME

        Estado = "ERROR";
        Mensaje = string(ME.message);

        ID_base_A = NaN;

        Vth_dyn_V = NaN;
        tVth_s = NaN;

        ID_punto_corr_A = NaN;
        ID_punto_original_A = NaN;
        dIDdt_punto_A_por_us = NaN;

        VGS_valle_V = NaN;
        tValle_s = NaN;
        ID_valle_corr_A = NaN;
        ID_valle_original_A = NaN;

        VGS_pico_V = NaN;
        tPico_s = NaN;
        ID_pico_corr_A = NaN;
        ID_pico_original_A = NaN;

        dIDdt_max_A_por_us = NaN;
        umbral_dIDdt_A_por_us = NaN;
        idxValle = NaN;
        idxInicioPendiente = NaN;
        idxPico = NaN;
    end

    % =========================================================
    %  AGREGAR RESULTADO A TABLA
    % =========================================================

    fila = table( ...
        Ciclo, ...
        string(nombreArchivo), ...
        Vth_dyn_V, ...
        tVth_s, ...
        tVth_s * 1e6, ...
        ID_punto_corr_A, ...
        ID_punto_corr_A * 1000, ...
        ID_punto_original_A, ...
        ID_punto_original_A * 1000, ...
        ID_base_A, ...
        dIDdt_punto_A_por_us, ...
        VGS_valle_V, ...
        tValle_s, ...
        tValle_s * 1e6, ...
        ID_valle_corr_A, ...
        ID_valle_corr_A * 1000, ...
        ID_valle_original_A, ...
        ID_valle_original_A * 1000, ...
        VGS_pico_V, ...
        tPico_s, ...
        tPico_s * 1e6, ...
        ID_pico_corr_A, ...
        ID_pico_corr_A * 1000, ...
        ID_pico_original_A, ...
        ID_pico_original_A * 1000, ...
        dIDdt_max_A_por_us, ...
        umbral_dIDdt_A_por_us, ...
        t_busqueda_min_us, ...
        t_busqueda_max_us, ...
        porcentaje_pendiente_inicio, ...
        ventana_suavizado, ...
        N_consecutivos_inicio, ...
        idxValle, ...
        idxInicioPendiente, ...
        idxPico, ...
        Estado, ...
        Mensaje, ...
        'VariableNames', { ...
            'Ciclo', ...
            'Archivo', ...
            'Vth_dinamico_V', ...
            'Tiempo_Vth_s', ...
            'Tiempo_Vth_us', ...
            'ID_corr_en_Vth_A', ...
            'ID_corr_en_Vth_mA', ...
            'ID_original_en_Vth_A', ...
            'ID_original_en_Vth_mA', ...
            'ID_base_A', ...
            'dIDdt_en_Vth_A_por_us', ...
            'VGS_valle_V', ...
            'Tiempo_valle_s', ...
            'Tiempo_valle_us', ...
            'ID_corr_valle_A', ...
            'ID_corr_valle_mA', ...
            'ID_original_valle_A', ...
            'ID_original_valle_mA', ...
            'VGS_pico_ventana_V', ...
            'Tiempo_pico_ventana_s', ...
            'Tiempo_pico_ventana_us', ...
            'ID_corr_pico_ventana_A', ...
            'ID_corr_pico_ventana_mA', ...
            'ID_original_pico_ventana_A', ...
            'ID_original_pico_ventana_mA', ...
            'dIDdt_max_A_por_us', ...
            'umbral_dIDdt_A_por_us', ...
            't_busqueda_min_us', ...
            't_busqueda_max_us', ...
            'porcentaje_pendiente_inicio', ...
            'ventana_suavizado', ...
            'N_consecutivos_inicio', ...
            'idx_valle', ...
            'idx_inicio_pendiente', ...
            'idx_pico_ventana', ...
            'Estado', ...
            'Mensaje'} ...
    );

    resultados = [resultados; fila]; %#ok<AGROW>

end

% =========================================================
%  ORDENAR RESULTADOS POR CICLO
% =========================================================

resultados = sortrows(resultados, 'Ciclo');

% =========================================================
%  GUARDAR CSV FINAL COMPLETO
% =========================================================

writetable(resultados, archivoResumen);

% =========================================================
%  GUARDAR CSV SIMPLE SOLO CICLO Y Vth
% =========================================================

resumenSimple = resultados(:, {'Ciclo', 'Archivo', 'Vth_dinamico_V', 'Estado'});
archivoResumenSimple = fullfile(rutaSalida, 'VTH_CICLO_SIMPLE.csv');

writetable(resumenSimple, archivoResumenSimple);

% =========================================================
%  MOSTRAR RESUMEN
% =========================================================

fprintf('\n=========================================\n');
fprintf('PROCESAMIENTO TERMINADO\n');
fprintf('Archivos procesados: %d\n', numel(archivos));
fprintf('CSV completo guardado en:\n%s\n', archivoResumen);
fprintf('\nCSV simple guardado en:\n%s\n', archivoResumenSimple);
fprintf('=========================================\n\n');

disp(resumenSimple);

% =========================================================
%  FUNCION LOCAL: EXTRAER CICLO DESDE NOMBRE
% =========================================================

function ciclo = extraer_ciclo_desde_nombre(nombreArchivo, indiceDefault)

    nombreLower = lower(nombreArchivo);

    % Busca patrones:
    %   CAPTURA_ON_CICLO_001
    %   CAPTURA_ON_CICLO001
    %   CAPTURA_ON_CICLO-001
    %   captura_on_ciclo 001

    tokensCiclo = regexp(nombreLower, 'ciclo[_\-\s]*(\d+)', 'tokens');

    if ~isempty(tokensCiclo)
        ciclo = str2double(tokensCiclo{1}{1});
        return;
    end

    % Si no encuentra "ciclo", toma el ultimo numero del nombre
    tokensNumeros = regexp(nombreLower, '(\d+)', 'tokens');

    if ~isempty(tokensNumeros)
        ciclo = str2double(tokensNumeros{end}{1});
    else
        ciclo = indiceDefault;
    end

end