clc
clear
clearvars

% =========================================================
%  GLOBALES
% =========================================================
global stopRequestedMaster ...
       sGlobalMaster vContGlobal vRapGlobal ...
       tInicioMaster ultimoTiempoTemp ultimoTiempoGuardadoVDSID ...
       figTemp axTemp hDUT hAMB hEXTRA pDUT pAMB pEXTRA txtDUT txtAMB txtEXTRA ...
       previewTemp ...
       cfgOut logFID ...
       yLimTemp yLimVDS yLimID yLimVGS yLimIG ...
       tempState figCtrl ...
       ioBuffer tekCache

stopRequestedMaster       = false;
tInicioMaster             = NaT;
ultimoTiempoTemp          = -inf;
ultimoTiempoGuardadoVDSID = -inf;

sGlobalMaster = [];
vContGlobal   = [];
vRapGlobal    = [];

% =========================================================
%  ESTADO DE TEMPERATURA
% =========================================================
tempState = struct();
tempState.lastDUT     = NaN;
tempState.lastAMB     = NaN;
tempState.lastEXTRA   = NaN;
tempState.haveDUT     = false;
tempState.haveAMB     = false;
tempState.haveEXTRA   = false;
tempState.lastFlush_s = -inf;
tempState.lastPlot_s  = -inf;

% =========================================================
%  BUFFERS / FILE I/O
% =========================================================
ioBuffer = struct();

ioBuffer.temp.rows      = zeros(0,4);   % [t dut amb extra]
ioBuffer.temp.maxRows   = 100;
ioBuffer.temp.fid       = -1;
ioBuffer.temp.bytesEst  = 0;
ioBuffer.temp.bytesRow  = 48;

ioBuffer.vdsid.rows     = zeros(0,3);   % [t vds id]
ioBuffer.vdsid.maxRows  = 2000;
ioBuffer.vdsid.fid      = -1;
ioBuffer.vdsid.bytesEst = 0;
ioBuffer.vdsid.bytesRow = 40;

% =========================================================
%  CACHE TEK
% =========================================================
tekCache = struct();
tekCache.cont = struct();
tekCache.rap  = struct();

% =========================================================
%  CONFIGURACION GENERAL
% =========================================================
resourceContinuo = "TCPIP0::10.7.30.102::inst0::INSTR";
resourceRapido   = "TCPIP0::10.7.30.193::inst0::INSTR";
puertoESP        = "COM3";
baudESP          = 115200;

Ton_ms         = 15000;
Toff_ms        = 15000;
tempIntervalMs = 250;
syncPulseUs    = 50;

% =========================================================
%  SCOPE CONTINUO VDS / ID
% =========================================================
periodoLecturaVDSID_s = 3.00;
recordLengthVDSID     = 5000;
canalSyncCont         = "CH1";
canalVDS              = "CH2";
canalID               = "CH3";

triggerLevelSYNC_V         = 1.5;
escalaInicioSyncCont_s_div = 20e-3;
pretriggerInicioCont_pct   = 20;
escalaContLibre_s_div      = 5.0;

% =========================================================
%  SCOPE RAPIDO VGS / IG / ID
% =========================================================
% RAM FIX:
% Antes estaba en 50000. Para una ventana total de 4 us, 10000 puntos
% sigue dando buena resolucion temporal y reduce bastante memoria/carga.
NptsRapido = 10000;

% ---------------------------------------------------------
% Ventana rapida total:
% 0.4 us/div * 10 div = 4 us total.
% Con pretrigger 50%: aprox. -2 us a +2 us.
% ---------------------------------------------------------
escalaRapida_s_div   = 0.4e-6;     % 400 ns/div -> 4 us total
pretriggerRapido_pct = 50;

canalRap.SYNC = "CH1";
canalRap.VGS  = "CH2";
canalRap.IG   = "CH3";
canalRap.ID   = "CH4";   % ID rapido

% Ajuste vertical para mejorar resolucion del ID rapido.
escalaIDRapido_A_div = 0.05;
posicionIDRapido_div = 0;

periodoCiclo_s         = (Ton_ms + Toff_ms)/1000;
timeoutCapturaRapida_s = max(1.2*periodoCiclo_s, 5);
rearmeRapido_s         = 0.08;

% =========================================================
%  LIMITES DE GRAFICAS
% =========================================================
yLimTemp = [0 400];
yLimVDS  = [-20 20];
yLimID   = [-5 20];
yLimVGS  = [-15 25];
yLimIG   = [-5 5];

% =========================================================
%  PREVIEW EN RAM SOLO PARA TEMPERATURA
% =========================================================
previewTemp.maxPts  = 600;
previewTemp.t       = [];
previewTemp.yDUT    = [];
previewTemp.yAMB    = [];
previewTemp.yEXTRA  = [];

% =========================================================
%  SALIDAS Y ROTACION
% =========================================================
stamp = datestr(now,'yyyy_mm_dd_HH_MM_SS');

cfgOut.baseFolder = sprintf('MAESTRO_LARGA_DURACION_%s', stamp);
if ~exist(cfgOut.baseFolder,'dir')
    mkdir(cfgOut.baseFolder);
end

cfgOut.tempBaseName    = 'TEMPERATURAS';
cfgOut.vdsidBaseName   = 'VDS_ID';
cfgOut.calcBaseName    = 'TDUT_TJ_RDSON';
cfgOut.vgsigFolderName = 'CAPTURAS_VGS_IG';

cfgOut.vgsigFolder = fullfile(cfgOut.baseFolder, cfgOut.vgsigFolderName);
if ~exist(cfgOut.vgsigFolder,'dir')
    mkdir(cfgOut.vgsigFolder);
end

cfgOut.logFile = fullfile(cfgOut.baseFolder, sprintf('LOG_%s.txt', stamp));
cfgOut.maxBytesPerFile = 10 * 1024 * 1024;

cfgOut.tempPart  = 1;
cfgOut.vdsidPart = 1;
cfgOut.calcPart  = 1;

cfgOut.tempCurrentFile  = fullfile(cfgOut.baseFolder, sprintf('%s_PARTE_%03d.csv', cfgOut.tempBaseName,  cfgOut.tempPart));
cfgOut.vdsidCurrentFile = fullfile(cfgOut.baseFolder, sprintf('%s_PARTE_%03d.csv', cfgOut.vdsidBaseName, cfgOut.vdsidPart));
cfgOut.calcCurrentFile  = fullfile(cfgOut.baseFolder, sprintf('%s_PARTE_%03d.csv', cfgOut.calcBaseName,  cfgOut.calcPart));

crear_csv_temperaturas(cfgOut.tempCurrentFile);
crear_csv_vdsid(cfgOut.vdsidCurrentFile);

logFID = fopen(cfgOut.logFile,'a');

log_msg('====================================================');
log_msg('INICIO SCRIPT SOLO ADQUISICION/GUARDADO ROBUSTO - RAM OPTIMIZADO');
log_msg(['Base folder : ' cfgOut.baseFolder]);
log_msg(['CSV TEMP    : ' cfgOut.tempCurrentFile]);
log_msg(['CSV VDS/ID  : ' cfgOut.vdsidCurrentFile]);
log_msg(['Carpeta VGS : ' cfgOut.vgsigFolder]);
log_msg('Rapido: CH1 SYNC, CH2 VGS, CH3 IG, CH4 ID rapido, ventana total 4 us, WIDTH 1/int8 compatible.');
log_msg(['Npts rapido : ' num2str(NptsRapido)]);
log_msg(['CH4 ID rapido SCALE: ' num2str(escalaIDRapido_A_div) ' A/div']);
log_msg(['Ventana rapida total: ' num2str(escalaRapida_s_div*10*1e6) ' us']);
log_msg('====================================================');

abrir_archivos_buffer();

% =========================================================
%  LIMPIEZA PREVIA
% =========================================================
oldSerial = serialportfind;
if ~isempty(oldSerial)
    delete(oldSerial);
end

try
    instrreset;
catch
end

try
    oldVisa = visadevfind;
    if ~isempty(oldVisa)
        for kk = 1:numel(oldVisa)
            try
                delete(oldVisa(kk));
            catch
            end
        end
    end
catch
end

% =========================================================
%  CONEXIONES
% =========================================================
vCont = visadev(resourceContinuo);
configureTerminator(vCont, "LF");
vCont.Timeout = 25;
writeline(vCont, "HEADER 0");
writeline(vCont, "VERBOSE 0");
writeline(vCont, "*IDN?");
fprintf('Scope continuo: %s\n', strtrim(readline(vCont)));
vContGlobal = vCont;

vRap = visadev(resourceRapido);
configureTerminator(vRap, "LF");
vRap.Timeout = 20;
writeline(vRap, "HEADER 0");
writeline(vRap, "VERBOSE 0");
writeline(vRap, "*IDN?");
fprintf('Scope rapido: %s\n', strtrim(readline(vRap)));
vRapGlobal = vRap;

s = serialport(puertoESP, baudESP);
configureTerminator(s, "LF");
pause(3);
flush(s);
sGlobalMaster = s;

% =========================================================
%  FIGURA DE CONTROL
% =========================================================
figCtrl = figure('Name','Maestro integrado MOSFET - SOLO adquisicion/guardado robusto', ...
    'NumberTitle','off', ...
    'CloseRequestFcn', @cerrarTodoMaster);

uicontrol('Style','pushbutton', ...
          'String','DETENER', ...
          'FontSize',14, ...
          'ForegroundColor','w', ...
          'BackgroundColor',[0.85 0 0], ...
          'Units','normalized', ...
          'Position',[0.25 0.35 0.50 0.30], ...
          'Callback', @botonDetenerMaster);

uicontrol('Style','text', ...
          'String','Solo adquisicion. Postproceso aparte. Escritura bufferizada y rotativa.', ...
          'Units','normalized', ...
          'Position',[0.05 0.72 0.90 0.10], ...
          'FontSize',11);

% =========================================================
%  FIGURA DE TEMPERATURA EN TIEMPO REAL
% =========================================================
figTemp = figure('Name','Temperaturas tiempo real', ...
                 'NumberTitle','off', ...
                 'CloseRequestFcn', @cerrarFiguraTempMaster);

axTemp = axes(figTemp);
hold(axTemp,'on');
hDUT   = plot(axTemp, NaN, NaN, 'm-', 'LineWidth',1.4, 'DisplayName','TEMP DUT');
hAMB   = plot(axTemp, NaN, NaN, 'g-', 'LineWidth',1.4, 'DisplayName','TEMP AMB');
hEXTRA = plot(axTemp, NaN, NaN, 'c-', 'LineWidth',1.4, 'DisplayName','TEMP EXTRA');
pDUT   = plot(axTemp, NaN, NaN, 'mo', 'MarkerFaceColor','m', 'HandleVisibility','off');
pAMB   = plot(axTemp, NaN, NaN, 'go', 'MarkerFaceColor','g', 'HandleVisibility','off');
pEXTRA = plot(axTemp, NaN, NaN, 'co', 'MarkerFaceColor','c', 'HandleVisibility','off');
txtDUT   = text(axTemp,0,0,'','Color','m','FontSize',10);
txtAMB   = text(axTemp,0,0,'','Color','g','FontSize',10);
txtEXTRA = text(axTemp,0,0,'','Color','c','FontSize',10);
grid(axTemp,'on');
xlabel(axTemp,'Tiempo (s)');
ylabel(axTemp,'Temperatura (°C)');
title(axTemp,'Temperaturas en tiempo real');
legend(axTemp,'Location','best');
ylim(axTemp,yLimTemp);
xlim(axTemp,[0 10]);

% =========================================================
%  INICIO
% =========================================================
resp = input('¿Iniciar adquisicion integrada? (s/n): ','s');
if lower(resp) ~= 's'
    limpiar_recursos();
    return
end

fprintf('\n====================================================\n');
fprintf('INICIO DE ADQUISICION INTEGRADA LARGA DURACION\n');
fprintf('Carpeta base          -> %s\n', cfgOut.baseFolder);
fprintf('Temperaturas          -> %s\n', cfgOut.tempCurrentFile);
fprintf('VDS / ID continuo     -> %s\n', cfgOut.vdsidCurrentFile);
fprintf('VGS / IG / ID rapido  -> %s\n', cfgOut.vgsigFolder);
fprintf('Npts rapido           -> %d\n', NptsRapido);
fprintf('ID rapido CH4 scale   -> %.3f A/div\n', escalaIDRapido_A_div);
fprintf('Ventana rapida total  -> %.3f us\n', escalaRapida_s_div*10*1e6);
fprintf('Pretrigger rapido     -> %.1f %%\n', pretriggerRapido_pct);
fprintf('Ventana aproximada    -> %.3f us antes / %.3f us despues del trigger\n', ...
    escalaRapida_s_div*10*1e6*(pretriggerRapido_pct/100), ...
    escalaRapida_s_div*10*1e6*(1 - pretriggerRapido_pct/100));
fprintf('====================================================\n\n');

clear leerESPtempMaster
configureCallback(s, "terminator", @leerESPtempMaster);

try
    writeline(s, "STOP");
    pause(0.3);
catch
end
flush(s);

% =========================================================
%  CONFIGURACION ESP
% =========================================================
writeline(s, "MODE:CONT");
pause(0.10);
writeline(s, "TON_MS:" + string(Ton_ms));
pause(0.05);
writeline(s, "TOFF_MS:" + string(Toff_ms));
pause(0.05);
writeline(s, "TEMP_INTERVAL_MS:" + string(tempIntervalMs));
pause(0.05);
writeline(s, "SYNC_US:" + string(syncPulseUs));
pause(0.05);

% =========================================================
%  PREPARAR SCOPES
% =========================================================
try
    configurar_tek_trigger_inicio_sync(vCont, ...
        escalaInicioSyncCont_s_div, ...
        canalSyncCont, ...
        triggerLevelSYNC_V, ...
        "RISE", ...
        pretriggerInicioCont_pct);
catch ME
    log_msg(['WARN preparar continuo: ' ME.message]);
end

try
    configurar_tek_trigger_rapido_sync(vRap, NptsRapido, escalaRapida_s_div, ...
        canalRap.SYNC, triggerLevelSYNC_V, "RISE", pretriggerRapido_pct, ...
        canalRap.ID, escalaIDRapido_A_div, posicionIDRapido_div);
catch ME
    log_msg(['WARN preparar rapido: ' ME.message]);
end

% =========================================================
%  ARM
% =========================================================
writeline(s, "ARM");
pause(0.40);

% =========================================================
%  ESTADO RAPIDO
% =========================================================
estadoRapido = struct();
estadoRapido.armado        = true;
estadoRapido.ciclo         = 1;
estadoRapido.tArmado_s     = 0;
estadoRapido.timeout_s     = timeoutCapturaRapida_s;
estadoRapido.rearme_s      = rearmeRapido_s;
estadoRapido.ultimoOK_s    = -inf;
estadoRapido.capturoON     = false;
estadoRapido.capturoOFF    = false;

% =========================================================
%  CONTINUO
% =========================================================
try
    configurar_scope_continuo_memoria(vCont, recordLengthVDSID, escalaContLibre_s_div);
catch ME
    log_msg(['WARN configurar continuo memoria: ' ME.message]);
end

% =========================================================
%  TIMERS
% =========================================================
ticGlobal           = tic;
tUltimaLecturaVDSID = tic;
tUltimoDrawnow      = tic;
tUltimoEstadoMAT    = tic;
tUltimoLogMem       = tic;
kCapturaRapida      = 0;

% =========================================================
%  PRIMER RECORD OFF ANTES DE GO
% =========================================================
tAhora0 = 0.0;
[tVDS0, yVDS0] = leer_waveform_tektronix_memoria_bin(vCont, canalVDS, recordLengthVDSID, 'cont');
[tID0,  yID0 ] = leer_waveform_tektronix_memoria_bin(vCont, canalID,  recordLengthVDSID, 'cont');

if ~(isempty(tVDS0) && isempty(tID0))
    Tinit = construir_memoria_desde_record_inicial(tAhora0, tVDS0, yVDS0, tID0, yID0);
    Tinit = limpiar_bloque_vdsid(Tinit, -inf);
    if ~isempty(Tinit) && height(Tinit) > 0
        append_table_vdsid_rotativo(Tinit);
        ultimoTiempoGuardadoVDSID = max(Tinit.TiempoGlobal_s);
        log_msg('Primer record OFF guardado antes de GO.');
    end
end
clear tVDS0 yVDS0 tID0 yID0 Tinit

pause(0.10);

% =========================================================
%  GO
% =========================================================
writeline(s, "GO");
tInicioMaster = datetime('now');
log_msg('GO enviado.');
log_memoria('inicio despues de GO');

% =========================================================
%  BUCLE PRINCIPAL CON PROTECCION
% =========================================================
try
    while ~stopRequestedMaster

        if toc(tUltimoDrawnow) >= 0.25
            drawnow limitrate
            tUltimoDrawnow = tic;
        end

        pause(0.002);

        % -------------------------------------------------
        % VDS / ID continuo
        % -------------------------------------------------
        if toc(tUltimaLecturaVDSID) >= periodoLecturaVDSID_s
            tUltimaLecturaVDSID = tic;
            tAhora = toc(ticGlobal);

            [tVDS, yVDS] = leer_waveform_tektronix_memoria_bin(vCont, canalVDS, recordLengthVDSID, 'cont');
            [tID,  yID ] = leer_waveform_tektronix_memoria_bin(vCont, canalID,  recordLengthVDSID, 'cont');

            if ~(isempty(tVDS) && isempty(tID))
                Tlocal = construir_memoria_desde_record( ...
                    tAhora, tVDS, yVDS, tID, yID, ultimoTiempoGuardadoVDSID);

                Tlocal = limpiar_bloque_vdsid(Tlocal, ultimoTiempoGuardadoVDSID);

                if ~isempty(Tlocal) && height(Tlocal) > 0
                    if bloque_valido_general(Tlocal, ultimoTiempoGuardadoVDSID)
                        append_table_vdsid_rotativo(Tlocal);
                        ultimoTiempoGuardadoVDSID = max(Tlocal.TiempoGlobal_s);
                    end
                end
            end

            clear tVDS yVDS tID yID Tlocal tAhora
            drawnow limitrate
        end

        % -------------------------------------------------
        % VGS / IG / ID rapido
        % -------------------------------------------------
        [estadoRapido, kCapturaRapida] = gestionar_captura_rapida( ...
            estadoRapido, ...
            toc(ticGlobal), ...
            vRap, ...
            canalRap, ...
            triggerLevelSYNC_V, ...
            NptsRapido, ...
            escalaRapida_s_div, ...
            pretriggerRapido_pct, ...
            kCapturaRapida, ...
            cfgOut.vgsigFolder, ...
            escalaIDRapido_A_div, ...
            posicionIDRapido_div);

        % -------------------------------------------------
        % Flush de seguridad de temperatura
        % -------------------------------------------------
        intentar_flush_temp(false);

        % -------------------------------------------------
        % Guardado de estado cada 5 min
        % RAM FIX: no guarda ioBuffer completo, solo resumen.
        % -------------------------------------------------
        if toc(tUltimoEstadoMAT) >= 300
            guardar_estado_seguridad(estadoRapido, kCapturaRapida);
            tUltimoEstadoMAT = tic;
        end

        % -------------------------------------------------
        % Monitoreo de memoria cada 10 min
        % -------------------------------------------------
        if toc(tUltimoLogMem) >= 600
            log_memoria('bucle principal');
            tUltimoLogMem = tic;
        end
    end

catch ME
    log_msg(['ERROR CRITICO EN BUCLE PRINCIPAL: ' ME.message]);

    try
        guardar_estado_seguridad(estadoRapido, kCapturaRapida);
    catch
    end

    try
        flush_all_buffers();
    catch
    end

    try
        cerrar_archivos_buffer();
    catch
    end

    try
        writeline(sGlobalMaster, "STOP");
    catch
    end

    try
        writeline(vContGlobal, "ACQUIRE:STATE STOP");
    catch
    end

    try
        writeline(vRapGlobal, "ACQUIRE:STATE STOP");
    catch
    end

    limpiar_recursos();
    rethrow(ME);
end

% =========================================================
%  PARO FINAL
% =========================================================
fprintf('\nDeteniendo adquisicion integrada...\n');
log_msg('Deteniendo adquisicion integrada...');

try
    writeline(s, "STOP");
catch
end

try
    configureCallback(s, "off");
catch
end

try
    writeline(vCont, "ACQUIRE:STATE STOP");
catch
end

try
    writeline(vRap, "ACQUIRE:STATE STOP");
catch
end

pause(0.2);

try
    intentar_flush_temp(true);
catch
end

try
    guardar_estado_seguridad(estadoRapido, kCapturaRapida);
catch
end

flush_all_buffers();
cerrar_archivos_buffer();
log_memoria('fin adquisicion antes de limpiar recursos');

fprintf('\n====================================================\n');
fprintf('FIN DE ADQUISICION INTEGRADA\n');
fprintf('Carpeta base -> %s\n', cfgOut.baseFolder);
fprintf('Ahora ejecuta el script de postproceso aparte.\n');
fprintf('====================================================\n');

log_msg('FIN DE ADQUISICION. Postproceso NO ejecutado en este script.');
limpiar_recursos();

% =========================================================
%  FUNCIONES
% =========================================================

function crear_csv_temperaturas(nombreCSV)
    fid = fopen(nombreCSV,'w');
    fprintf(fid, 'Tiempo_s,TEMP_DUT_C,TEMP_AMB_C,TEMP_EXTRA_C\n');
    fclose(fid);
end

function crear_csv_vdsid(nombreCSV)
    fid = fopen(nombreCSV,'w');
    fprintf(fid, 'TiempoGlobal_s,VDS_V,ID_A\n');
    fclose(fid);
end

function log_msg(msg)
    global logFID
    try
        if ~isempty(logFID) && logFID > 0
            fprintf(logFID, '[%s] %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS.FFF'), msg);
        end
    catch
    end
    fprintf('%s\n', msg);
end

function log_memoria(etiqueta)
    global logFID
    try
        m = memory;
        ramMATLAB_GB = m.MemUsedMATLAB / 1024^3;
        ramLibre_GB  = m.PhysicalMemory.Available / 1024^3;
        ramTotal_GB  = m.PhysicalMemory.Total / 1024^3;

        msg = sprintf('[MEM] %s | MATLAB: %.3f GB | Libre: %.3f GB | Total: %.3f GB', ...
            etiqueta, ramMATLAB_GB, ramLibre_GB, ramTotal_GB);

        fprintf('%s\n', msg);

        if ~isempty(logFID) && logFID > 0
            fprintf(logFID, '[%s] %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'), msg);
        end
    catch
        % memory funciona principalmente en Windows.
    end
end

function abrir_archivos_buffer()
    global ioBuffer cfgOut

    ioBuffer.temp.fid = fopen(cfgOut.tempCurrentFile, 'a');
    if ioBuffer.temp.fid < 0
        error('No se pudo abrir archivo TEMP');
    end

    ioBuffer.vdsid.fid = fopen(cfgOut.vdsidCurrentFile, 'a');
    if ioBuffer.vdsid.fid < 0
        error('No se pudo abrir archivo VDS/ID');
    end

    ioBuffer.temp.bytesEst  = get_file_bytes(cfgOut.tempCurrentFile);
    ioBuffer.vdsid.bytesEst = get_file_bytes(cfgOut.vdsidCurrentFile);
end

function cerrar_archivos_buffer()
    global ioBuffer

    try
        if ~isempty(ioBuffer.temp.fid) && ioBuffer.temp.fid > 0
            fclose(ioBuffer.temp.fid);
        end
    catch
    end
    ioBuffer.temp.fid = -1;

    try
        if ~isempty(ioBuffer.vdsid.fid) && ioBuffer.vdsid.fid > 0
            fclose(ioBuffer.vdsid.fid);
        end
    catch
    end
    ioBuffer.vdsid.fid = -1;
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

function leerESPtempMaster(src, ~)
    global tInicioMaster stopRequestedMaster tempState

    try
        if stopRequestedMaster
            return
        end

        dato = strtrim(readline(src));
        if strlength(string(dato)) == 0
            return
        end

        if any(strcmpi(dato, {"DONE","FINISHED","END","STOPPED"}))
            return
        end

        mensajesIgnorar = ["ESP_LISTO","ALL_OUTPUTS_OFF","STOP_OK", ...
                           "TEMP_INTERVAL_MS_OK:","TEMP_INTERVAL_MS:", ...
                           "GO_OK","ARM_OK","MODE_CONT_OK","MODE_CYCLES_OK", ...
                           "ESTADO:ON","ESTADO:OFF","ESTADO:OFF_ARMED"];
        for i = 1:numel(mensajesIgnorar)
            if startsWith(string(dato), mensajesIgnorar(i), 'IgnoreCase', true)
                return
            end
        end

        if isnat(tInicioMaster)
            return
        end

        tAbs = tiempo_unico(seconds(datetime('now') - tInicioMaster));

        if startsWith(upper(dato), "TEMP_DUT:")
            temp = str2double(extractAfter(dato, "TEMP_DUT:"));
            if ~isnan(temp)
                tempState.lastDUT = temp;
                tempState.haveDUT = true;
                intentar_flush_temp(false, tAbs);
            end
            return
        end

        if startsWith(upper(dato), "TEMP_AMB:")
            temp = str2double(extractAfter(dato, "TEMP_AMB:"));
            if ~isnan(temp)
                tempState.lastAMB = temp;
                tempState.haveAMB = true;
                intentar_flush_temp(false, tAbs);
            end
            return
        end

        if startsWith(upper(dato), "TEMP_EXTRA:")
            temp = str2double(extractAfter(dato, "TEMP_EXTRA:"));
            if ~isnan(temp)
                tempState.lastEXTRA = temp;
                tempState.haveEXTRA = true;
                intentar_flush_temp(true, tAbs);
            end
            return
        end
    catch
    end
end

function intentar_flush_temp(forzar, tAbs)
    global tempState
    if nargin < 2
        tAbs = NaN;
    end

    if isnan(tAbs)
        if tempState.haveDUT || tempState.haveAMB || tempState.haveEXTRA
            tAbs = tempState.lastFlush_s + 1e-3;
        else
            return
        end
    end

    if ~(tempState.haveDUT && tempState.haveAMB && tempState.haveEXTRA)
        if ~forzar
            return
        end
        if ~(isfinite(tempState.lastDUT) || isfinite(tempState.lastAMB) || isfinite(tempState.lastEXTRA))
            return
        end
    end

    tRow = tAbs;
    if isfinite(tempState.lastFlush_s) && tRow <= tempState.lastFlush_s
        tRow = tempState.lastFlush_s + 1e-6;
    end

    append_temp_row_rotativo_completo(tRow, tempState.lastDUT, tempState.lastAMB, tempState.lastEXTRA);

    if ~isfield(tempState,'lastPlot_s') || ~isfinite(tempState.lastPlot_s)
        tempState.lastPlot_s = -inf;
    end

    if (tRow - tempState.lastPlot_s) >= 2.0
        actualizar_preview_temp(tRow, tempState.lastDUT, tempState.lastAMB, tempState.lastEXTRA);
        tempState.lastPlot_s = tRow;
    end

    tempState.lastFlush_s = tRow;
    tempState.haveDUT   = false;
    tempState.haveAMB   = false;
    tempState.haveEXTRA = false;
end

function actualizar_preview_temp(tAbs, dut, amb, extra)
    global previewTemp figTemp axTemp hDUT hAMB hEXTRA pDUT pAMB pEXTRA txtDUT txtAMB txtEXTRA

    previewTemp.t      = append_limit(previewTemp.t,      tAbs, previewTemp.maxPts);
    previewTemp.yDUT   = append_limit(previewTemp.yDUT,   dut,  previewTemp.maxPts);
    previewTemp.yAMB   = append_limit(previewTemp.yAMB,   amb,  previewTemp.maxPts);
    previewTemp.yEXTRA = append_limit(previewTemp.yEXTRA, extra, previewTemp.maxPts);

    if isempty(figTemp) || ~isvalid(figTemp) || isempty(axTemp) || ~isvalid(axTemp)
        return
    end

    actualizar_grafica_temp_tripleta( ...
        hDUT, hAMB, hEXTRA, pDUT, pAMB, pEXTRA, txtDUT, txtAMB, txtEXTRA, ...
        previewTemp.t, previewTemp.yDUT, previewTemp.yAMB, previewTemp.yEXTRA, axTemp);
end

function append_temp_row_rotativo_completo(t, dut, amb, extra)
    global ioBuffer
    ioBuffer.temp.rows(end+1, :) = [t dut amb extra];
    if size(ioBuffer.temp.rows,1) >= ioBuffer.temp.maxRows
        flush_temp_buffer();
    end
end

function flush_temp_buffer()
    global ioBuffer cfgOut
    if isempty(ioBuffer.temp.rows)
        return
    end

    rotar_si_necesario('temp', size(ioBuffer.temp.rows,1));

    fid = ioBuffer.temp.fid;
    A = ioBuffer.temp.rows;

    fprintf(fid, '%.9f,%.9f,%.9f,%.9f\n', A.');

    ioBuffer.temp.bytesEst = ioBuffer.temp.bytesEst + size(A,1)*ioBuffer.temp.bytesRow;
    ioBuffer.temp.rows = zeros(0,4);

    % Cierre/reapertura cada flush para seguridad de datos.
    try
        fclose(fid);
    catch
    end
    ioBuffer.temp.fid = fopen(cfgOut.tempCurrentFile, 'a');
end

function append_table_vdsid_rotativo(T)
    global ioBuffer
    if isempty(T) || height(T) == 0
        return
    end

    M = [T.TiempoGlobal_s, T.VDS_V, T.ID_A];
    ioBuffer.vdsid.rows = [ioBuffer.vdsid.rows; M]; %#ok<AGROW>

    if size(ioBuffer.vdsid.rows,1) >= ioBuffer.vdsid.maxRows
        flush_vdsid_buffer();
    end
end

function flush_vdsid_buffer()
    global ioBuffer cfgOut
    if isempty(ioBuffer.vdsid.rows)
        return
    end

    rotar_si_necesario('vdsid', size(ioBuffer.vdsid.rows,1));

    fid = ioBuffer.vdsid.fid;
    A = ioBuffer.vdsid.rows;

    fprintf(fid, '%.9f,%.9f,%.9f\n', A.');

    ioBuffer.vdsid.bytesEst = ioBuffer.vdsid.bytesEst + size(A,1)*ioBuffer.vdsid.bytesRow;
    ioBuffer.vdsid.rows = zeros(0,3);

    % Cierre/reapertura cada flush para seguridad de datos.
    try
        fclose(fid);
    catch
    end
    ioBuffer.vdsid.fid = fopen(cfgOut.vdsidCurrentFile, 'a');
end

function flush_all_buffers()
    flush_temp_buffer();
    flush_vdsid_buffer();
end

function rotar_si_necesario(tipo, nRowsIncoming)
    global cfgOut ioBuffer
    if nargin < 2
        nRowsIncoming = 1;
    end

    switch lower(tipo)
        case 'temp'
            bytesFuturos = ioBuffer.temp.bytesEst + nRowsIncoming*ioBuffer.temp.bytesRow;
            if bytesFuturos >= cfgOut.maxBytesPerFile
                try
                    if ioBuffer.temp.fid > 0
                        fclose(ioBuffer.temp.fid);
                    end
                catch
                end
                cfgOut.tempPart = cfgOut.tempPart + 1;
                cfgOut.tempCurrentFile = fullfile(cfgOut.baseFolder, ...
                    sprintf('%s_PARTE_%03d.csv', cfgOut.tempBaseName, cfgOut.tempPart));
                crear_csv_temperaturas(cfgOut.tempCurrentFile);
                ioBuffer.temp.fid = fopen(cfgOut.tempCurrentFile, 'a');
                ioBuffer.temp.bytesEst = get_file_bytes(cfgOut.tempCurrentFile);
                log_msg(['Rotacion TEMP -> ' cfgOut.tempCurrentFile]);
            end

        case 'vdsid'
            bytesFuturos = ioBuffer.vdsid.bytesEst + nRowsIncoming*ioBuffer.vdsid.bytesRow;
            if bytesFuturos >= cfgOut.maxBytesPerFile
                try
                    if ioBuffer.vdsid.fid > 0
                        fclose(ioBuffer.vdsid.fid);
                    end
                catch
                end
                cfgOut.vdsidPart = cfgOut.vdsidPart + 1;
                cfgOut.vdsidCurrentFile = fullfile(cfgOut.baseFolder, ...
                    sprintf('%s_PARTE_%03d.csv', cfgOut.vdsidBaseName, cfgOut.vdsidPart));
                crear_csv_vdsid(cfgOut.vdsidCurrentFile);
                ioBuffer.vdsid.fid = fopen(cfgOut.vdsidCurrentFile, 'a');
                ioBuffer.vdsid.bytesEst = get_file_bytes(cfgOut.vdsidCurrentFile);
                log_msg(['Rotacion VDS/ID -> ' cfgOut.vdsidCurrentFile]);
            end
    end
end

function vec = append_limit(vec, x, maxPts)
    vec = [vec; x];
    if numel(vec) > maxPts
        vec = vec(end-maxPts+1:end);
    end
end

function tOut = tiempo_unico(tIn)
    global ultimoTiempoTemp
    tOut = tIn;
    if tOut <= ultimoTiempoTemp
        tOut = ultimoTiempoTemp + 1e-6;
    end
    ultimoTiempoTemp = tOut;
end

function actualizar_grafica_temp_tripleta(hDUT, hAMB, hEXTRA, pDUT, pAMB, pEXTRA, txtDUT, txtAMB, txtEXTRA, tVec, yDUT, yAMB, yEXTRA, ax)
    if isempty(tVec) || ~isvalid(ax)
        return
    end

    idx1 = isfinite(yDUT);
    idx2 = isfinite(yAMB);
    idx3 = isfinite(yEXTRA);

    set(hDUT, "XData", tVec(idx1), "YData", yDUT(idx1));
    set(hAMB, "XData", tVec(idx2), "YData", yAMB(idx2));
    set(hEXTRA, "XData", tVec(idx3), "YData", yEXTRA(idx3));

    if any(idx1)
        id = find(idx1,1,'last');
        set(pDUT, "XData", tVec(id), "YData", yDUT(id));
        set(txtDUT, "Position", [tVec(id) yDUT(id) 0], "String", sprintf('%.2f °C', yDUT(id)));
    end
    if any(idx2)
        ia = find(idx2,1,'last');
        set(pAMB, "XData", tVec(ia), "YData", yAMB(ia));
        set(txtAMB, "Position", [tVec(ia) yAMB(ia) 0], "String", sprintf('%.2f °C', yAMB(ia)));
    end
    if any(idx3)
        ie = find(idx3,1,'last');
        set(pEXTRA, "XData", tVec(ie), "YData", yEXTRA(ie));
        set(txtEXTRA, "Position", [tVec(ie) yEXTRA(ie) 0], "String", sprintf('%.2f °C', yEXTRA(ie)));
    end

    xMax = max(10, tVec(end));
    xlim(ax, [max(0, xMax-600) xMax]);
end

function configurar_scope_continuo_memoria(v, recordLength, escalaContLibre_s_div)
    writeline(v, "ACQUIRE:STATE STOP"); pause(0.03);
    writeline(v, "CLEAR"); pause(0.03);

    writeline(v, "ACQUIRE:MODE SAMPLE"); pause(0.02);
    writeline(v, "ACQUIRE:STOPAFTER RUNSTOP"); pause(0.02);

    writeline(v, "HORIZONTAL:MODE MANUAL"); pause(0.02);
    writeline(v, "HORIZONTAL:DELAY:MODE OFF"); pause(0.02);
    writeline(v, "HORIZONTAL:SCALE " + string(escalaContLibre_s_div)); pause(0.02);
    writeline(v, "HORIZONTAL:RECORDLENGTH " + string(recordLength)); pause(0.02);

    writeline(v, "TRIGGER:A:MODE AUTO"); pause(0.02);

    writeline(v, "DATA:ENC RIBINARY"); pause(0.02);
    writeline(v, "DATA:WIDTH 1"); pause(0.02);
    writeline(v, "ACQUIRE:STATE RUN"); pause(0.02);
end

function [t, y] = leer_waveform_tektronix_memoria_bin(v, canal, NptsMax, cacheType)
    global tekCache
    t = [];
    y = [];

    try
        writeline(v,"DATA:SOURCE " + canal);
        writeline(v,"DATA:ENC RIBINARY");
        writeline(v,"DATA:WIDTH 1");

        writeline(v,"HORIZONTAL:RECORDLENGTH?");
        recLenReal = str2double(strtrim(readline(v)));
        if isnan(recLenReal) || recLenReal <= 0
            recLenReal = NptsMax;
        end
        recLen = min(recLenReal, NptsMax);

        writeline(v,"DATA:START 1");
        writeline(v,"DATA:STOP " + string(recLen));

        needMeta = true;
        switch lower(cacheType)
            case 'cont'
                if isfield(tekCache.cont, char(canal))
                    C = tekCache.cont.(char(canal));
                    if isfield(C,'recLen') && isequal(C.recLen, recLen)
                        needMeta = false;
                    end
                end
            case 'rap'
                if isfield(tekCache.rap, char(canal))
                    C = tekCache.rap.(char(canal));
                    if isfield(C,'recLen') && isequal(C.recLen, recLen)
                        needMeta = false;
                    end
                end
        end

        if needMeta
            writeline(v,"WFMOUTPRE:XINCR?");
            xincr = str2double(strtrim(readline(v)));
            writeline(v,"WFMOUTPRE:XZERO?");
            xzero = str2double(strtrim(readline(v)));
            writeline(v,"WFMOUTPRE:PT_OFF?");
            pt_off = str2double(strtrim(readline(v)));
            writeline(v,"WFMOUTPRE:YMULT?");
            ymult = str2double(strtrim(readline(v)));
            writeline(v,"WFMOUTPRE:YOFF?");
            yoff  = str2double(strtrim(readline(v)));
            writeline(v,"WFMOUTPRE:YZERO?");
            yzero = str2double(strtrim(readline(v)));

            if any(isnan([xincr xzero pt_off ymult yoff yzero]))
                return
            end

            C = struct('xincr',xincr,'xzero',xzero,'pt_off',pt_off, ...
                       'ymult',ymult,'yoff',yoff,'yzero',yzero,'recLen',recLen);

            switch lower(cacheType)
                case 'cont'
                    tekCache.cont.(char(canal)) = C;
                case 'rap'
                    tekCache.rap.(char(canal)) = C;
            end
        else
            switch lower(cacheType)
                case 'cont'
                    C = tekCache.cont.(char(canal));
                case 'rap'
                    C = tekCache.rap.(char(canal));
            end
        end

        writeline(v,"CURVE?");
        datos = readbinblock(v,"int8");
        try
            read(v, 1, "uint8");
        catch
        end

        if isempty(datos)
            return
        end

        datos = double(datos(:));
        if numel(datos) > recLen
            datos = datos(1:recLen);
        end

        y = ((datos - C.yoff) * C.ymult) + C.yzero;
        y(abs(y) < 1e-9) = 0;

        n = (0:length(datos)-1).';
        t = C.xzero + (n - C.pt_off) * C.xincr;
    catch
        t = [];
        y = [];
    end
end

function configurar_tek_trigger_inicio_sync(v, escala_s_div, canalTrigger, nivelTrigger_V, slopeMode, pretriggerPct)
    writeline(v, "ACQUIRE:STATE STOP"); pause(0.03);
    writeline(v, "CLEAR"); pause(0.03);

    writeline(v, "ACQUIRE:MODE SAMPLE"); pause(0.02);
    writeline(v, "ACQUIRE:STOPAFTER RUNSTOP"); pause(0.02);

    writeline(v, "HORIZONTAL:MODE MANUAL"); pause(0.02);
    writeline(v, "HORIZONTAL:DELAY:MODE OFF"); pause(0.02);
    writeline(v, "HORIZONTAL:POSITION " + string(pretriggerPct)); pause(0.02);
    writeline(v, "HORIZONTAL:SCALE " + string(escala_s_div)); pause(0.02);

    writeline(v, "DATA:ENC RIBINARY"); pause(0.02);
    writeline(v, "DATA:WIDTH 1"); pause(0.02);

    writeline(v, "TRIGGER:A:TYPE EDGE"); pause(0.02);
    writeline(v, "TRIGGER:A:MODE NORMAL"); pause(0.02);
    writeline(v, "TRIGGER:A:EDGE:SOURCE " + canalTrigger); pause(0.02);
    writeline(v, "TRIGGER:A:EDGE:COUPLING DC"); pause(0.02);
    writeline(v, "TRIGGER:A:EDGE:SLOPE " + slopeMode); pause(0.02);

    try
        writeline(v, "TRIGGER:A:LEVEL:" + canalTrigger + " " + string(nivelTrigger_V));
    catch
        writeline(v, "TRIGGER:A:LEVEL " + string(nivelTrigger_V));
    end

    try
        writeline(v, "TRIGGER:A:HOLDoff:TIME 0");
    catch
    end

    writeline(v, "ACQUIRE:STATE RUN");
    pause(0.03);
end

function configurar_tek_trigger_rapido_sync(v, Npts, escala_s_div, canalTrigger, nivelTrigger_V, slopeMode, pretriggerPct, canalIDRapido, escalaIDRapido_A_div, posicionIDRapido_div)
    writeline(v, "ACQUIRE:STATE STOP"); pause(0.02);
    writeline(v, "ACQUIRE:MODE SAMPLE"); pause(0.02);
    writeline(v, "ACQUIRE:STOPAFTER SEQUENCE"); pause(0.02);
    writeline(v, "HORIZONTAL:MODE MANUAL"); pause(0.02);
    writeline(v, "HORIZONTAL:DELAY:MODE OFF"); pause(0.02);
    writeline(v, "HORIZONTAL:POSITION " + string(pretriggerPct)); pause(0.02);
    writeline(v, "HORIZONTAL:SCALE " + string(escala_s_div)); pause(0.02);
    writeline(v, "HORIZONTAL:RECORDLENGTH " + string(Npts)); pause(0.02);

    writeline(v, "DATA:ENC RIBINARY"); pause(0.02);
    writeline(v, "DATA:WIDTH 1"); pause(0.02);
    writeline(v, "DATA:START 1"); pause(0.02);
    writeline(v, "DATA:STOP " + string(Npts)); pause(0.02);

    writeline(v, "TRIGGER:A:TYPE EDGE"); pause(0.02);
    writeline(v, "TRIGGER:A:MODE NORMAL"); pause(0.02);
    writeline(v, "TRIGGER:A:EDGE:SOURCE " + canalTrigger); pause(0.02);
    writeline(v, "TRIGGER:A:EDGE:COUPLING DC"); pause(0.02);
    writeline(v, "TRIGGER:A:EDGE:SLOPE " + slopeMode); pause(0.02);

    try
        writeline(v, "TRIGGER:A:LEVEL:" + canalTrigger + " " + string(nivelTrigger_V));
    catch
        writeline(v, "TRIGGER:A:LEVEL " + string(nivelTrigger_V));
    end

    try
        writeline(v, "TRIGGER:A:HOLDoff:TIME 0");
    catch
    end

    try
        writeline(v, canalIDRapido + ":SCALE " + string(escalaIDRapido_A_div));
        pause(0.02);
        writeline(v, canalIDRapido + ":POSITION " + string(posicionIDRapido_div));
        pause(0.02);
    catch
    end

    writeline(v, "ACQUIRE:STATE RUN");
    pause(0.02);
end

function Tlocal = construir_memoria_desde_record_inicial(tAhora, tVDS, yVDS, tID, yID)
    Tlocal = table();

    tMaster = escoger_tiempo_maestro_2(tVDS, tID);
    if isempty(tMaster)
        return
    end

    vds = interp_seguro(tVDS, yVDS, tMaster);
    id  = interp_seguro(tID,  yID,  tMaster);

    if all(isnan(vds)) && all(isnan(id))
        return
    end

    tLoc = tMaster(:);
    tLoc = tLoc - tLoc(1);

    spanReal_s = tLoc(end);
    tGlobal = tAhora - spanReal_s + tLoc;

    Tlocal = table(tGlobal(:), vds(:), id(:), ...
        'VariableNames', {'TiempoGlobal_s','VDS_V','ID_A'});
end

function Tlocal = construir_memoria_desde_record(tAhora, tVDS, yVDS, tID, yID, ultimoTiempoGuardado)
    Tlocal = table();

    tMaster = escoger_tiempo_maestro_2(tVDS, tID);
    if isempty(tMaster)
        return
    end

    vds = interp_seguro(tVDS, yVDS, tMaster);
    id  = interp_seguro(tID,  yID,  tMaster);

    if all(isnan(vds)) && all(isnan(id))
        return
    end

    tLoc = tMaster(:);
    tLoc = tLoc - tLoc(1);

    spanReal_s = tLoc(end);
    tGlobal = tAhora - spanReal_s + tLoc;

    idxNew = tGlobal > (ultimoTiempoGuardado + 1e-6);

    tGlobal = tGlobal(idxNew);
    vds     = vds(idxNew);
    id      = id(idxNew);

    if isempty(tGlobal)
        return
    end

    Tlocal = table(tGlobal(:), vds(:), id(:), ...
        'VariableNames', {'TiempoGlobal_s','VDS_V','ID_A'});
end

function Tlocal = limpiar_bloque_vdsid(Tlocal, ultimoTiempoGuardado)
    if isempty(Tlocal) || height(Tlocal) == 0
        return
    end

    Tlocal = Tlocal(isfinite(Tlocal.TiempoGlobal_s), :);
    if isempty(Tlocal), return; end

    Tlocal = sortrows(Tlocal, 'TiempoGlobal_s');

    dt = [true; diff(Tlocal.TiempoGlobal_s) > 0];
    Tlocal = Tlocal(dt, :);

    if isempty(Tlocal), return; end

    Tlocal = Tlocal(Tlocal.TiempoGlobal_s > ultimoTiempoGuardado + 1e-6, :);

    if isempty(Tlocal), return; end

    idxSmallV = isfinite(Tlocal.VDS_V) & abs(Tlocal.VDS_V) < 1e-9;
    idxSmallI = isfinite(Tlocal.ID_A)  & abs(Tlocal.ID_A)  < 1e-9;
    Tlocal.VDS_V(idxSmallV) = 0;
    Tlocal.ID_A(idxSmallI)  = 0;
end

function ok = bloque_valido_general(Tlocal, ultimoTiempoGuardado)
    ok = true;

    if isempty(Tlocal) || height(Tlocal) == 0
        ok = false; return
    end

    t = Tlocal.TiempoGlobal_s;
    if any(~isfinite(t))
        ok = false; return
    end

    if any(diff(t) <= 0)
        ok = false; return
    end

    if isfinite(ultimoTiempoGuardado)
        if max(t) <= ultimoTiempoGuardado
            ok = false; return
        end
        if min(t) < (ultimoTiempoGuardado - 5)
            ok = false; return
        end
    end
end

function [t, y, yUnit] = leer_waveform_tektronix_raw_bin(v, canal, Npts)
    global tekCache
    t = [];
    y = [];
    yUnit = "";

    try
        writeline(v,"DATA:SOURCE " + canal);
        writeline(v,"DATA:ENC RIBINARY");
        writeline(v,"DATA:WIDTH 1");

        writeline(v,"HORIZONTAL:RECORDLENGTH?");
        recLenReal = str2double(strtrim(readline(v)));
        if isnan(recLenReal) || recLenReal <= 0
            recLenReal = Npts;
        end
        recLen = min(recLenReal, Npts);

        writeline(v,"DATA:START 1");
        writeline(v,"DATA:STOP " + string(recLen));

        needMeta = true;
        if isfield(tekCache.rap, char(canal))
            C = tekCache.rap.(char(canal));
            if isfield(C,'recLen') && isequal(C.recLen, recLen) && isfield(C,'width') && C.width == 1
                needMeta = false;
            end
        end

        if needMeta
            writeline(v,"WFMOUTPRE:XINCR?"); xincr = str2double(strtrim(readline(v)));
            writeline(v,"WFMOUTPRE:XZERO?"); xzero = str2double(strtrim(readline(v)));
            writeline(v,"WFMOUTPRE:PT_OFF?"); pt_off = str2double(strtrim(readline(v)));
            writeline(v,"WFMOUTPRE:YMULT?"); ymult = str2double(strtrim(readline(v)));
            writeline(v,"WFMOUTPRE:YOFF?");  yoff  = str2double(strtrim(readline(v)));
            writeline(v,"WFMOUTPRE:YZERO?"); yzero = str2double(strtrim(readline(v)));

            try
                writeline(v,"WFMOUTPRE:YUNIT?");
                yUnit = strtrim(readline(v));
                yUnit = erase(yUnit, '"');
            catch
                yUnit = "";
            end

            if any(isnan([xincr xzero pt_off ymult yoff yzero]))
                return
            end

            C = struct('xincr',xincr,'xzero',xzero,'pt_off',pt_off, ...
                       'ymult',ymult,'yoff',yoff,'yzero',yzero, ...
                       'recLen',recLen,'yUnit',yUnit,'width',1);
            tekCache.rap.(char(canal)) = C;
        else
            C = tekCache.rap.(char(canal));
            if isfield(C,'yUnit')
                yUnit = C.yUnit;
            else
                yUnit = "";
            end
        end

        writeline(v,"CURVE?");
        datos = readbinblock(v,"int8");
        try
            read(v, 1, "uint8");
        catch
        end

        if isempty(datos)
            return
        end

        datos = double(datos(:));
        if numel(datos) > recLen
            datos = datos(1:recLen);
        end

        y = ((datos - C.yoff) * C.ymult) + C.yzero;
        y(abs(y) < 1e-12) = 0;

        n = (0:length(datos)-1).';
        t = C.xzero + (n - C.pt_off) * C.xincr;
    catch
        t = [];
        y = [];
        yUnit = "";
    end
end

function ok = detectar_flanco_en_sync(ySYNC)
    ok = false;
    if isempty(ySYNC) || numel(ySYNC) < 20
        return
    end

    y = ySYNC(:);
    y = y(~isnan(y));
    if numel(y) < 20
        return
    end

    excursion = max(y) - min(y);
    if excursion < 0.5
        return
    end

    dy = abs(diff(y));
    if isempty(dy)
        return
    end

    ok = max(dy) > 0;
end

function T = construir_tabla_rapida_vgs_ig_id(tSYNC, ySYNC, tVGS, yVGS, tIG, yIG, tIDr, yIDr)
    tMaster = escoger_tiempo_maestro_4(tSYNC, tVGS, tIG, tIDr);
    if isempty(tMaster)
        T = table();
        return
    end

    sync = interp_seguro(tSYNC, ySYNC, tMaster);
    vgs  = interp_seguro(tVGS,  yVGS,  tMaster);
    ig   = interp_seguro(tIG,   yIG,   tMaster);
    id   = interp_seguro(tIDr,  yIDr,  tMaster);

    T = table(tMaster(:), sync(:), vgs(:), ig(:), id(:), ...
        'VariableNames', {'TiempoLocal_s','SYNC_V','VGS_V','IG_A','ID_A'});
end

function [estadoRapido, kCapturaRapida] = gestionar_captura_rapida( ...
    estadoRapido, tNow_s, vRap, canalRap, triggerLevelSYNC_V, ...
    NptsRapido, escalaRapida_s_div, pretriggerRapido_pct, ...
    kCapturaRapida, carpetaVGSIG, escalaIDRapido_A_div, posicionIDRapido_div)

    if ~estadoRapido.armado
        try
            configurar_tek_trigger_rapido_sync( ...
                vRap, NptsRapido, escalaRapida_s_div, ...
                canalRap.SYNC, triggerLevelSYNC_V, "RISE", pretriggerRapido_pct, ...
                canalRap.ID, escalaIDRapido_A_div, posicionIDRapido_div);

            estadoRapido.armado    = true;
            estadoRapido.tArmado_s = tNow_s;
        catch
            estadoRapido.armado    = false;
            estadoRapido.tArmado_s = tNow_s;
        end
        return
    end

    yaDisparo = secuencia_rapida_terminada(vRap);

    if yaDisparo
        try
            writeline(vRap, "ACQUIRE:STATE STOP");
        catch
        end

        [tSYNC, ySYNC, ~] = leer_waveform_tektronix_raw_bin(vRap, canalRap.SYNC, NptsRapido);
        [tVGS,  yVGS,  ~] = leer_waveform_tektronix_raw_bin(vRap, canalRap.VGS,  NptsRapido);
        [tIG,   yIG,   ~] = leer_waveform_tektronix_raw_bin(vRap, canalRap.IG,   NptsRapido);
        [tIDr,  yIDr,  ~] = leer_waveform_tektronix_raw_bin(vRap, canalRap.ID,   NptsRapido);

        okSync = detectar_flanco_en_sync(ySYNC);
        tipoEvento = clasificar_evento_desde_vgs(yVGS);

        guardarEstaCaptura = false;

        if okSync && tipoEvento ~= "NONE"
            if tipoEvento == "ON" && ~estadoRapido.capturoON
                guardarEstaCaptura = true;
            elseif tipoEvento == "OFF" && ~estadoRapido.capturoOFF
                guardarEstaCaptura = true;
            end
        end

        if guardarEstaCaptura
            Trap = construir_tabla_rapida_vgs_ig_id(tSYNC, ySYNC, tVGS, yVGS, tIG, yIG, tIDr, yIDr);

            if ~isempty(Trap) && height(Trap) > 0
                kCapturaRapida = kCapturaRapida + 1;

                Trap.Captura = repmat(kCapturaRapida, height(Trap), 1);
                Trap.Ciclo   = repmat(estadoRapido.ciclo, height(Trap), 1);
                Trap.Evento  = repmat(tipoEvento, height(Trap), 1);
                Trap = movevars(Trap, {'Captura','Ciclo','Evento'}, 'Before', 1);

                nombreCSVcap = fullfile(carpetaVGSIG, ...
                    sprintf('CAPTURA_%s_CICLO_%06d_%06d_%s.csv', ...
                    char(tipoEvento), ...
                    estadoRapido.ciclo, ...
                    kCapturaRapida, ...
                    datestr(now,'HH_MM_SS_FFF')));

                writetable(Trap, nombreCSVcap);

                % RAM FIX:
                % Ya NO se guarda Trap en primeraCapturaON/primeraCapturaOFF.
                % La captura queda guardada en CSV y se libera de RAM.
                guardar_primera_captura(Trap, tipoEvento);

                estadoRapido.ultimoOK_s = tNow_s;

                if tipoEvento == "ON"
                    estadoRapido.capturoON = true;
                elseif tipoEvento == "OFF"
                    estadoRapido.capturoOFF = true;
                end

                if estadoRapido.capturoON && estadoRapido.capturoOFF
                    estadoRapido.ciclo = estadoRapido.ciclo + 1;
                    estadoRapido.capturoON = false;
                    estadoRapido.capturoOFF = false;
                end
            end
        end

        clear tSYNC ySYNC tVGS yVGS tIG yIG tIDr yIDr Trap ...
              okSync tipoEvento guardarEstaCaptura nombreCSVcap
        drawnow limitrate

        estadoRapido.armado    = false;
        estadoRapido.tArmado_s = tNow_s;
        pause(estadoRapido.rearme_s);
        return
    end

    if (tNow_s - estadoRapido.tArmado_s) > estadoRapido.timeout_s
        try
            writeline(vRap, "ACQUIRE:STATE STOP");
        catch
        end
        estadoRapido.armado    = false;
        estadoRapido.tArmado_s = tNow_s;
        pause(estadoRapido.rearme_s);
    end
end

function guardar_primera_captura(~, ~)
    % RAM FIX:
    % Para adquisicion larga no se guardan capturas completas en RAM.
    % Las capturas rapidas ya se guardan como CSV en CAPTURAS_VGS_IG.
end

function tipoEvento = clasificar_evento_desde_vgs(yVGS)
    tipoEvento = "NONE";

    if isempty(yVGS) || numel(yVGS) < 50
        return
    end

    y = yVGS(:);
    y = y(~isnan(y));

    if numel(y) < 50
        return
    end

    n = numel(y);
    nSeg = max(10, round(0.10*n));

    yIni = median(y(1:nSeg));
    yFin = median(y(end-nSeg+1:end));

    dV = yFin - yIni;

    if dV > 5
        tipoEvento = "ON";
    elseif dV < -5
        tipoEvento = "OFF";
    end
end

function ok = secuencia_rapida_terminada(v)
    ok = false;
    try
        writeline(v, "ACQUIRE:STATE?");
        r = strtrim(readline(v));

        val = str2double(r);
        if ~isnan(val)
            ok = (val == 0);
            return
        end

        rU = upper(string(r));
        if contains(rU, "STOP") || contains(rU, "SAVE") || strcmp(strtrim(r), "0")
            ok = true;
        end
    catch
        ok = false;
    end
end

function tMaster = escoger_tiempo_maestro_2(t1, t2)
    tMaster = [];
    n1 = 0; n2 = 0;

    if ~isempty(t1), n1 = numel(t1); end
    if ~isempty(t2), n2 = numel(t2); end

    if n1 >= n2 && n1 > 0
        tMaster = t1(:);
    elseif n2 > 0
        tMaster = t2(:);
    end
end

function tMaster = escoger_tiempo_maestro_4(t1, t2, t3, t4)
    candidatos = {t1, t2, t3, t4};
    tMaster = [];
    longitudes = zeros(numel(candidatos),1);

    for k = 1:numel(candidatos)
        if ~isempty(candidatos{k})
            longitudes(k) = numel(candidatos{k});
        end
    end

    [~, idx] = max(longitudes);
    if longitudes(idx) > 0
        tMaster = candidatos{idx}(:);
    end
end

function yq = interp_seguro(t, y, tq)
    yq = nan(size(tq));

    if isempty(t) || isempty(y) || numel(t) < 2 || numel(y) < 2
        return
    end

    t = t(:);
    y = y(:);
    tq = tq(:);

    idxValid = ~(isnan(t) | isnan(y));
    t = t(idxValid);
    y = y(idxValid);

    if numel(t) < 2
        return
    end

    [t, idxSort] = sort(t);
    y = y(idxSort);
    [tUnique, idxUnique] = unique(t, 'stable');
    yUnique = y(idxUnique);

    if numel(tUnique) < 2
        return
    end

    yq = interp1(tUnique, yUnique, tq, 'linear', NaN);
end

function guardar_estado_seguridad(estadoRapido, kCapturaRapida)
    global cfgOut ultimoTiempoGuardadoVDSID tempState ioBuffer

    try
        archivoEstado = fullfile(cfgOut.baseFolder, 'ESTADO_ULTIMO.mat');

        % RAM FIX:
        % No se guarda ioBuffer completo porque puede incluir filas pendientes
        % y campos de archivos abiertos. Solo se guarda resumen operativo.
        estadoBuffer = struct();
        estadoBuffer.tempRowsPendientes  = size(ioBuffer.temp.rows,1);
        estadoBuffer.vdsidRowsPendientes = size(ioBuffer.vdsid.rows,1);
        estadoBuffer.tempFileActual      = cfgOut.tempCurrentFile;
        estadoBuffer.vdsidFileActual     = cfgOut.vdsidCurrentFile;
        estadoBuffer.tempPart            = cfgOut.tempPart;
        estadoBuffer.vdsidPart           = cfgOut.vdsidPart;
        estadoBuffer.tempBytesEst        = ioBuffer.temp.bytesEst;
        estadoBuffer.vdsidBytesEst       = ioBuffer.vdsid.bytesEst;

        save(archivoEstado, ...
            'cfgOut', ...
            'ultimoTiempoGuardadoVDSID', ...
            'tempState', ...
            'estadoRapido', ...
            'kCapturaRapida', ...
            'estadoBuffer', ...
            '-v7');
    catch
    end
end

function botonDetenerMaster(~, ~)
    global stopRequestedMaster sGlobalMaster vContGlobal vRapGlobal
    stopRequestedMaster = true;

    try
        if ~isempty(sGlobalMaster), writeline(sGlobalMaster, "STOP"); end
    catch
    end
    try
        if ~isempty(vContGlobal), writeline(vContGlobal, "ACQUIRE:STATE STOP"); end
    catch
    end
    try
        if ~isempty(vRapGlobal), writeline(vRapGlobal, "ACQUIRE:STATE STOP"); end
    catch
    end
end

function cerrarTodoMaster(~, ~)
    botonDetenerMaster();
    try
        delete(gcf);
    catch
    end
end

function cerrarFiguraTempMaster(~, ~)
    global stopRequestedMaster sGlobalMaster
    stopRequestedMaster = true;
    try
        if ~isempty(sGlobalMaster), writeline(sGlobalMaster, "STOP"); end
    catch
    end
    try
        delete(gcf);
    catch
    end
end

function limpiar_recursos()
    global sGlobalMaster vContGlobal vRapGlobal logFID

    try
        flush_all_buffers();
    catch
    end

    try
        cerrar_archivos_buffer();
    catch
    end

    try
        if ~isempty(sGlobalMaster)
            configureCallback(sGlobalMaster, "off");
        end
    catch
    end

    try
        if ~isempty(sGlobalMaster)
            delete(sGlobalMaster);
        end
    catch
    end

    try
        if ~isempty(vContGlobal)
            delete(vContGlobal);
        end
    catch
    end

    try
        if ~isempty(vRapGlobal)
            delete(vRapGlobal);
        end
    catch
    end

    try
        if ~isempty(logFID) && logFID > 0
            fclose(logFID);
        end
    catch
    end
end
