/* =========================================================================
   29 - HU-008 CA-03: reportes del costo labor en un solo procedimiento

   Origen: Scripts/script_reportes.sql. Ese script arma el calculo como una
   cadena de CTE y al final se elige con un SELECT cual mirar. Aqui se
   conserva esa idea: la cadena de CTE se escribe una sola vez y el SELECT
   final se arma dinamicamente segun @codReporte, en vez de crear un
   procedimiento por reporte.

   @codReporte es el nombre del CTE que se quiere consultar. Son los siete
   reportes del Excel del contador, en el orden de sus hojas:

     1  BD_REP19                      vouchers de gasto del periodo
     2  RESUMEN_GRAL_GASTO_PERSONAL   total por tipo de gasto, descripcion y cuenta
     3  DETALLE_GASTO_PERSONAL        mano de obra por trabajador, con OTROS
     4  RESUMEN_GASTO_PERSONAL        mano de obra por gerencia
     5  RESUMEN_COSTO_LABOR           CORE 1 / CORE 2: gasto de personal,
                                      gasto operativo y compensacion
     6  BD_DISTRIBUCION_COMPENSACION  vouchers de compensacion del periodo
     7  DISTRIBUCION_COMPENSACION     monto y compensacion por fuente y proyecto
     8  HH_POR_PROYECTO               horas validadas por colaborador y proyecto
                                      (pestania 4 de la HU-008)
     9  TOTAL_COSTO_LABOR             mano de obra, gasto operativo y compensacion
                                      por fuente y proyecto (pestania 5)

   Ningun reporte trae filas ni columnas de totales: los totales los arma el
   Excel con formulas de suma (pedido de Efrain, 15/09/2026).

   Diferencias con el script original:
     - Lee de proceso.TMD_GASTO_PERSONAL y proceso.TMD_DISTRIBUCION_COMPENSACION,
       que usp_Periodo_Procesar llena con la misma consulta a BD_SPRING. Asi
       el reporte muestra lo que se proceso y aprobo, y un periodo cerrado no
       cambia aunque SPRING cambie despues.
     - @codReporte se valida contra una lista fija y el nombre se pasa por
       QUOTENAME: el texto que llega del backend nunca se concatena tal cual.
     - OTROS multiplica antes de dividir para no perder decimales, y no
       divide entre cero si el mes no tiene sueldos ni asignacion familiar.
     - Los totales que salen vacios (por ejemplo, un mes sin Gerente General)
       valen 0 en vez de volver NULL todo el resumen.
     - La gerencia sale abreviada (GAF, GG, GIP, GL, GO, OCI), como en el Excel
       del contador; la Oficina de Planeamiento y Mejora Continua cuenta como GG.
       Una division que no esta en la lista conserva su nombre y no entra en
       ningun Core.
     - DISTRIBUCION_COMPENSACION muestra el proyecto como en el Excel:
       ultimos seis digitos del codigo, guion y nombre (000058-AZALIA Y PUCARA).
     - El 40/60 del Gerente General y la tasa de compensacion del 7 % ya no
       estan fijos: se leen de general.TG_CONFIGURACION, igual que DIST_GIP y
       DIST_GO. Si falta alguno, el reporte falla en vez de calcular con cero.

   Reparto por proyecto (reportes 8 y 9)

   Replica las hojas "HH por proyecto 2", "Distribucion MO (Calculo)",
   "Distribucion GO" y "Total Costo Labor" del Excel del contador (enero 2025):

     1. Horas: TMD_REGISTRO_HORAMES de los trabajadores con el mes CONFORME
        (HU-008 CA-02 pide las horas validadas).
     2. Proporcion por departamento (DGO, DIP, DPCM, RRCC): cada subordinado
        reparte sus horas ajustadas (las ejecutadas, o HORAS_MES_REFERENCIA si
        trabajo menos) segun su peso, que es horas / referencia * sueldo.
        Jefes y administrativos siguen la proporcion de su departamento; el
        personal de la Gerencia de Operaciones, la mezcla de los cuatro
        departamentos ponderada por el gasto de personal de cada uno.
     3. Mano de obra del proyecto: gasto de personal de cada trabajador del
        periodo segun su proporcion, mas la parte Core 2 del Gerente General
        (promedio simple de las cuatro proporciones) y de las areas de apoyo
        (DIST_GO_* por departamento). Lo de GIP y las partes Core 1 van a la
        fila PROINVERSION.
     4. Gasto operativo: PORC_GO_* por departamento segun su proporcion; la
        parte DIST_GIP va a PROINVERSION.
     5. Compensacion: la del reporte 7, por proyecto.

   Diferencias con el Excel, por datos que el sistema no tiene:
     - El peso usa los sueldos y salarios del mes (cuenta 62110010) y no la
       remuneracion basica de las planillas.
     - Las horas de referencia salen de HORAS_MES_REFERENCIA (168 = 21 dias por
       8 horas en enero 2025) y no de una celda por mes.
     - Un subordinado sin horas validadas sigue la proporcion de su
       departamento en vez de quedar sin repartir.

   Un periodo sin procesar devuelve el resultado vacio, igual que
   usp_GastoPersonal_Listar.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   Parametros del costo labor en TG_CONFIGURACION

   Mismo formato que la distribucion de la HU-002: porcentaje con dos
   decimales en txtParametro. No usan el prefijo DIST_ porque la pantalla de
   la HU-002 valida que los DIST_ sumen 100 %, y estos no forman parte de ese
   reparto. Solo se inserta lo que falta, para no pisar cambios posteriores.
   ------------------------------------------------------------------------- */
DECLARE @configuraciones TABLE (codigo varchar(30), numValor int, txtValor varchar(100), descripcion varchar(200));

INSERT INTO @configuraciones (codigo, numValor, txtValor, descripcion) VALUES
    ('PORC_GG_CORE1',        NULL, '40.00', 'Gerente General asignado a la Linea Core 1 (GIP)'),
    ('PORC_GG_CORE2',        NULL, '60.00', 'Gerente General asignado a la Linea Core 2 (GO)'),
    ('PORC_COMPENSACION',    NULL, '7.00',  'Tasa de compensacion sobre el monto por proyecto'),
    -- Incidencia del gasto operativo aprobada por la GAF (HU-009 CA-02); GIP es DIST_GIP.
    ('PORC_GO_DGO',          NULL, '60.00', 'Gasto operativo del Departamento de Gestion de Obras'),
    ('PORC_GO_DIP',          NULL, '8.00',  'Gasto operativo del Departamento de Ingenieria de Proyectos'),
    ('PORC_GO_DPCM',         NULL, '30.00', 'Gasto operativo del Departamento de Post Cierre y Mantenimiento'),
    ('PORC_GO_RRCC',         NULL, '1.50',  'Gasto operativo de Relaciones Comunitarias'),
    ('HORAS_MES_REFERENCIA', 168,  NULL,    'Horas laborables del mes para ajustar las horas por proyecto');

INSERT INTO general.TG_CONFIGURACION
      (txtCodigoConfiguracion, numParametro, txtParametro, numMinimo, numMaximo,
       txtDescripcion, flgEstado, fecCreacion, txtUsuarioCreacion)
SELECT c.codigo, c.numValor, c.txtValor, NULL, NULL, c.descripcion, 1, GETDATE(), 'SYSTEM_COSTOLABOR'
FROM @configuraciones c
WHERE NOT EXISTS (SELECT 1 FROM general.TG_CONFIGURACION t
                  WHERE t.txtCodigoConfiguracion = c.codigo);
GO

/* -------------------------------------------------------------------------
   Catalogo de proyectos y su fuente de financiamiento

   El reparto por proyecto agrupa por fuente, y ni TMD_PERIODO_PROYECTO ni las
   horas la guardan. La semilla es la hoja "Proyectos" del Excel del contador.
   codProyecto va con los 12 digitos de SPRING; se cruza por los ultimos seis,
   que es como lo guardan las horas.
   ------------------------------------------------------------------------- */
IF OBJECT_ID('proceso.TMC_PROYECTO_FUENTE') IS NULL
BEGIN
    CREATE TABLE proceso.TMC_PROYECTO_FUENTE(
        ideProyectoFuente bigint IDENTITY(1,1) NOT NULL,
        codProyecto varchar(30) NOT NULL,
        codFuente varchar(20) NOT NULL,
        nomProyecto varchar(200) NOT NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMC_PROYECTO_FUENTE_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMC_PROYECTO_FUENTE_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(30) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(30) NULL,
        CONSTRAINT PK_TMC_PROYECTO_FUENTE PRIMARY KEY CLUSTERED (ideProyectoFuente ASC)
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMC_PROYECTO_FUENTE_codProyecto
        ON proceso.TMC_PROYECTO_FUENTE (codProyecto) WHERE flgEstado = 1;
END
GO

DECLARE @proyectos TABLE (codProyecto varchar(30), codFuente varchar(20), nomProyecto varchar(200));

INSERT INTO @proyectos (codProyecto, codFuente, nomProyecto) VALUES
    ('000000000075', '28E', 'NUEVO MUNDO'),
    ('000000000076', '28E', 'ISLAY'),
    ('000000000077', '28E', 'PARAGON'),
    ('000000000078', '28E', 'HUACRISH'),
    ('000000000079', '28E', 'FARALLON'),
    ('000000000080', '28E', 'MINA SAN GREGORIO'),
    ('000000000081', '28E', 'DE AZUFRE YUCAMANE'),
    ('000000000082', '28E', 'CCELLO CCELLO'),
    ('000000000083', '28E', 'TUMIRI'),
    ('000000000084', '28E', 'SAN DIEGO'),
    ('000000000085', '28E', 'EL LUCERO'),
    ('000000000087', '28E', 'MINA PUCPUSH'),
    ('000000000088', '28E', 'PLANTA CONSUSO'),
    ('000000000089', '28E', 'EL MOJON'),
    ('000000000090', '28E', 'APARRE'),
    ('000000000091', '28E', 'CHAHUAPAMPA'),
    ('000000000092', '28E', 'MINA SANTA ANITA'),
    ('000000000093', '28E', 'PATRICIA'),
    ('000000000094', '28E', 'LA CIENAGA'),
    ('000000000095', '28E', 'LA FLORIDA I'),
    ('000000000096', '28E', 'CANAY'),
    ('000000000097', '28E', 'TAMBORAS'),
    ('000000000098', '28E', 'NUEVA ESPERANZA 1'),
    ('000000000099', '28E', 'GAZUNA Y NUEVO OYON'),
    ('000000000100', '28E', 'SANTON'),
    ('000000000101', '28E', 'SANTA TERESITA'),
    ('000000000102', '28E', 'SANTA RITA-HUAURA'),
    ('000000000086', '28E', 'CAUDALOSA'),
    ('000000000001', 'FA', 'AREAS AFECTADAS POR EL DESMANTELAMIENTO DEL CABLE CARRIL'),
    ('000000000007', 'FA', 'PLAN DE CIERRE QUIULACOCHA'),
    ('000000000009', 'FA', 'MICHIQUILLAY - MANTENIMIENTO'),
    ('000000000013', 'FA', 'LA OROYA - CALIDAD DE AIRE'),
    ('000000000027', 'FA', 'CALIOC Y CHACRAPUQUIO'),
    ('000000000029', 'FA', 'CHUCCHIS 1ERA Y 2DA ZONA'),
    ('000000000040', 'FA', 'MARGEN IZQUIERDO'),
    ('000000000041', 'FA', 'DEPOSITO DE SUELOS CONTAMINADOS VADO MALPASO HUAYNACANCHA - MANTENIMIENTO'),
    ('000000000057', 'FA', 'DELTA FA'),
    ('000000000058', 'FA', 'AZALIA Y PUCARA - MANTENIMIENTO'),
    ('000000000065', 'FA', 'SAN FRANCISCO - LADERAS'),
    ('000000000104', 'FA', 'SAN JUAN FA'),
    ('000000000108', 'FA', 'AZALIA Y PUCARA - ESTUDIOS'),
    ('000000202009', 'FA', 'CASAPALCA - MANTENIMIENTO'),
    ('000000203008', 'FA', 'PUENTE CHUMPE Y TINCO'),
    ('000000210033', 'FA', 'HUAYNACANCHA'),
    ('000000210034', 'FA', 'CHUCCHIS'),
    ('000000210035', 'FA', 'MARCAVALLE'),
    ('000000210045', 'FA', 'CALLES TUPAC AMARU'),
    ('000000220014', 'FA', 'QUIULACOCHA-PLANTA DE TRATAMIENTO'),
    ('000000220017', 'FA', 'QUIULACOCHA MITIGACION'),
    ('000000230073', 'FA', 'EXCELSIOR'),
    ('000000000018', 'PAR', 'DELTA - PAAR'),
    ('000000000019', 'PAR', '5 RELAVERAS'),
    ('000000000020', 'PAR', 'DORADO Y BARRAGAN'),
    ('000000000021', 'PAR', 'LOS NEGROS'),
    ('000000000022', 'PAR', 'LA PASTORA'),
    ('000000000023', 'PAR', 'CLEOPATRA'),
    ('000000321016', 'PAR', 'CAUDALOSA 1'),
    ('000000000103', 'PAR', 'SAN JUAN PAAR'),
    ('000000210043', 'PAR', 'PISTAS Y VEREDAS JUAN PABLO II'),
    ('000000302002', 'PAR', 'HUAMUYO'),
    ('000000302004', 'PAR', 'ACOBAMBA Y COLQUI'),
    ('000000302006', 'PAR', 'CARIDAD'),
    ('000000302007', 'PAR', 'HUANCHURINA'),
    ('000000310031', 'PAR', 'LICHICOCHA'),
    ('000000310032', 'PAR', 'CARHUACAYAN'),
    ('000000321001', 'PAR', 'AZULMINA 1 Y 2'),
    ('000000340001', 'PAR', 'ESQUILACHE'),
    ('000000340002', 'PAR', 'ALADINO VI'),
    ('000000350001', 'PAR', 'PUSHAQUILCA'),
    ('000000364001', 'PAR', 'SANTA ROSA 2'),
    ('000000632025', 'PAR', '64 PASIVOS - MANTENIMIENTO'),
    ('000000632026', 'PAR', '64 PASIVOS - ESTUDIOS'),
    ('000000000074', 'TUCARI', 'TUCARI'),
    ('000000000105', 'TUQUIAR', 'ARASI'),
    ('000000000106', 'TUQUIAR', 'QUIRUVILCA'),
    ('000000000107', 'TUQUIAR', 'TUCARI PLAN DE CIERRE');

INSERT INTO proceso.TMC_PROYECTO_FUENTE (codProyecto, codFuente, nomProyecto, flgEstado, txtUsuarioCreacion)
SELECT p.codProyecto, p.codFuente, p.nomProyecto, 1, 'SYSTEM_COSTOLABOR'
FROM @proyectos p
WHERE NOT EXISTS (SELECT 1 FROM proceso.TMC_PROYECTO_FUENTE t WHERE t.codProyecto = p.codProyecto);
GO

CREATE OR ALTER PROCEDURE proceso.usp_Reporte_CostoLabor
    @numAnio    int,
    @numMes     int,
    @codReporte varchar(40)
AS
BEGIN
    SET NOCOUNT ON;

    /* ------------------------------------------------ Reporte solicitado */
    DECLARE @reportes TABLE (codReporte sysname PRIMARY KEY, txtOrden nvarchar(400) NOT NULL);
    INSERT INTO @reportes (codReporte, txtOrden) VALUES
        ('BD_REP19',                     N'voucherno, voucherline'),
        ('RESUMEN_GRAL_GASTO_PERSONAL',  N'txtTipoGasto, account'),
        ('DETALLE_GASTO_PERSONAL',       N'txtNombreCompleto'),
        ('RESUMEN_GASTO_PERSONAL',       N'GERENCIA'),
        ('RESUMEN_COSTO_LABOR',          N'CORE'),
        ('BD_DISTRIBUCION_COMPENSACION', N'txtCategoria, Proyecto, voucherno'),
        ('DISTRIBUCION_COMPENSACION',    N'FUENTE, PROYECTO'),
        ('HH_POR_PROYECTO',              N'CASE DEPARTAMENTO WHEN ''DGO'' THEN 1 WHEN ''DIP'' THEN 2 WHEN ''DPCM'' THEN 3 WHEN ''RRCC'' THEN 4 WHEN ''GO'' THEN 5 ELSE 6 END, '
                                         + N'CASE NIVEL WHEN ''GERENTE'' THEN 0 WHEN ''JEFE'' THEN 1 WHEN ''ADMINISTRATIVO'' THEN 2 ELSE 3 END, COLABORADOR'),
        ('TOTAL_COSTO_LABOR',            N'CASE FUENTE WHEN ''FA'' THEN 1 WHEN ''PAR'' THEN 2 WHEN ''28E'' THEN 3 WHEN ''TUCARI'' THEN 4 '
                                         + N'WHEN ''TUQUIAR'' THEN 5 WHEN ''PROINVERSION'' THEN 7 ELSE 6 END, PROYECTOS');

    DECLARE @cte sysname, @orden nvarchar(400);
    SELECT @cte = codReporte, @orden = txtOrden
    FROM @reportes
    WHERE codReporte = UPPER(LTRIM(RTRIM(@codReporte)));

    IF @cte IS NULL
    BEGIN
        DECLARE @mensaje nvarchar(200) = CONCAT(N'El reporte ', ISNULL(@codReporte, N'(vacio)'), N' no existe.');
        THROW 50040, @mensaje, 1;
    END

    /* ------------------------------------------------------- Parametros */
    DECLARE @idePeriodo bigint = (SELECT idePeriodo FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes);

    DECLARE @porcentajes TABLE (codigo varchar(30) PRIMARY KEY, valor decimal(14,4) NULL);
    INSERT INTO @porcentajes (codigo, valor)
    SELECT txtCodigoConfiguracion, TRY_CAST(txtParametro AS decimal(14,4))
    FROM general.TG_CONFIGURACION
    WHERE flgEstado = 1
      AND txtCodigoConfiguracion IN ('DIST_GIP', 'DIST_GO', 'PORC_GG_CORE1', 'PORC_GG_CORE2', 'PORC_COMPENSACION',
                                     'DIST_GO_GESTION_OBRAS', 'DIST_GO_ING_PROYECTOS', 'DIST_GO_POST_CIERRE',
                                     'DIST_GO_REL_COMUNITARIAS', 'PORC_GO_DGO', 'PORC_GO_DIP', 'PORC_GO_DPCM', 'PORC_GO_RRCC');

    DECLARE @porcDistGip      decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'DIST_GIP');
    DECLARE @porcDistGo       decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'DIST_GO');
    DECLARE @porcGerenteCore1 decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'PORC_GG_CORE1');
    DECLARE @porcGerenteCore2 decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'PORC_GG_CORE2');
    DECLARE @porcCompensacion decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'PORC_COMPENSACION');

    -- Areas de apoyo por departamento: la misma distribucion de la HU-002.
    DECLARE @porcEscDgo  decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'DIST_GO_GESTION_OBRAS');
    DECLARE @porcEscDip  decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'DIST_GO_ING_PROYECTOS');
    DECLARE @porcEscDpcm decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'DIST_GO_POST_CIERRE');
    DECLARE @porcEscRrcc decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'DIST_GO_REL_COMUNITARIAS');

    -- Gasto operativo por departamento (HU-009 CA-02).
    DECLARE @porcGoDgo  decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'PORC_GO_DGO');
    DECLARE @porcGoDip  decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'PORC_GO_DIP');
    DECLARE @porcGoDpcm decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'PORC_GO_DPCM');
    DECLARE @porcGoRrcc decimal(14,4) = (SELECT valor FROM @porcentajes WHERE codigo = 'PORC_GO_RRCC');

    DECLARE @horasReferencia decimal(14,4) = (SELECT CAST(numParametro AS decimal(14,4)) FROM general.TG_CONFIGURACION
                                              WHERE txtCodigoConfiguracion = 'HORAS_MES_REFERENCIA' AND flgEstado = 1);

    -- Un porcentaje ausente daria montos en cero que parecen correctos.
    IF @porcDistGip IS NULL OR @porcDistGo IS NULL OR @porcGerenteCore1 IS NULL
       OR @porcGerenteCore2 IS NULL OR @porcCompensacion IS NULL
       OR @porcEscDgo IS NULL OR @porcEscDip IS NULL OR @porcEscDpcm IS NULL OR @porcEscRrcc IS NULL
       OR @porcGoDgo IS NULL OR @porcGoDip IS NULL OR @porcGoDpcm IS NULL OR @porcGoRrcc IS NULL
        THROW 50041, 'Faltan porcentajes del costo labor en general.TG_CONFIGURACION (DIST_*, PORC_GG_*, PORC_GO_* o PORC_COMPENSACION).', 1;

    IF ISNULL(@horasReferencia, 0) <= 0
        THROW 50042, 'Falta HORAS_MES_REFERENCIA en general.TG_CONFIGURACION: debe ser mayor a cero.', 1;

    /* --------------------------------------------- Cadena de CTE comun */
    DECLARE @sql nvarchar(max) = N'
WITH BD_REP19 AS (
    SELECT g.voucherno, g.txtTipoGasto, g.voucherline, g.vendor, g.status, g.txtLocalName,
           ISNULL(g.localamount, 0) AS localamount, g.idePersona, g.txtNombreCompleto, g.account,
           g.Documento, g.Area, g.Departamento, g.Cargo, g.CostCenter, g.CentroCostos, g.period
    FROM proceso.TMD_GASTO_PERSONAL g
    WHERE g.idePeriodo = @idePeriodo AND g.flgEstado = 1
),

RESUMEN_GRAL_GASTO_PERSONAL AS (
    SELECT txtTipoGasto, txtLocalName, account, SUM(localamount) AS TOTAL
    FROM BD_REP19
    GROUP BY txtTipoGasto, txtLocalName, account
),

TOTAL_PROVEEDORES AS (
    SELECT CAST(ISNULL(SUM(localamount), 0) AS decimal(14,4)) AS TOTAL
    FROM BD_REP19
    WHERE txtTipoGasto = ''Gasto de Personal'' AND ISNULL(Area, '''') = ''''
),

TOTAL_SUELDOS_Y_SALARIOS AS (
    SELECT CAST(ISNULL(SUM(localamount), 0) AS decimal(14,4)) AS TOTAL
    FROM BD_REP19
    WHERE txtTipoGasto = ''Gasto de Personal'' AND account = ''62110010''
),

TOTAL_ASIGNACION_FAMILIAR AS (
    SELECT CAST(ISNULL(SUM(localamount), 0) AS decimal(14,4)) AS TOTAL
    FROM BD_REP19
    WHERE txtTipoGasto = ''Gasto de Personal'' AND account = ''62200010''
),

-- Siglas de gerencia del Excel del contador, a partir de HR_Division.DescripcionLarga.
GERENCIAS AS (
    -- CAST: sin el, el tipo sale de las siglas (varchar(3)) y una division fuera de la lista se trunca.
    SELECT Area, CAST(Gerencia AS varchar(200)) AS Gerencia
    FROM (VALUES (''GERENCIA DE ADMINISTRACION Y FINANZAS'', ''GAF''),
                 (''GERENCIA GENERAL'',                      ''GG''),
                 (''GERENCIA DE INVERSION PRIVADA'',         ''GIP''),
                 (''GERENCIA LEGAL'',                        ''GL''),
                 (''GERENCIA DE OPERACIONES'',               ''GO''),
                 (''OFICINA DE CONTROL INSTITUCIONAL'',      ''OCI''),
                 -- El contador la suma a la Gerencia General (Excel de enero 2025).
                 (''OFICINA DE PLANEAMIENTO Y MEJORA CONTINUA'', ''GG'')) AS g(Area, Gerencia)
),

-- Mano de obra por trabajador. OTROS reparte el gasto de proveedores sin area
-- en proporcion a (sueldos + asignacion familiar) de cada uno.
DETALLE_BASE AS (
    SELECT r.vendor, r.txtNombreCompleto, r.Documento, r.Area, r.Departamento,
        COALESCE(ge.Gerencia, r.Area) AS Gerencia,
        r.Cargo,
        CAST(SUM(CASE WHEN account = ''62110010'' THEN localamount ELSE 0 END) AS decimal(14,4)) AS SUELDOS_Y_SALARIOS,
        CAST(SUM(CASE WHEN account = ''62140010'' THEN localamount ELSE 0 END) AS decimal(14,4)) AS GRATIFICACIONES,
        CAST(SUM(CASE WHEN account = ''62150010'' THEN localamount ELSE 0 END) AS decimal(14,4)) AS VACACIONES,
        CAST(SUM(CASE WHEN account = ''62200010'' THEN localamount ELSE 0 END) AS decimal(14,4)) AS ASIGNACION_FAMILIAR,
        CAST(SUM(CASE WHEN account = ''62710010'' THEN localamount ELSE 0 END) AS decimal(14,4)) AS REGIMEN_DE_PRESTACIONES_DE_SALUD,
        CAST(SUM(CASE WHEN account = ''62750010'' THEN localamount ELSE 0 END) AS decimal(14,4)) AS SEGUROS_PARTICULARES_DE_SALUD_EPS_Y_OTROS_PARTIC,
        CAST(SUM(CASE WHEN account = ''62910010'' THEN localamount ELSE 0 END) AS decimal(14,4)) AS COMPENSACION_POR_TIEMPO_DE_SERVICIO
    FROM BD_REP19 r
    LEFT JOIN GERENCIAS ge ON ge.Area = r.Area
    WHERE r.txtTipoGasto = ''Gasto de Personal''
    GROUP BY r.vendor, r.txtNombreCompleto, r.Documento, r.Area, r.Departamento, COALESCE(ge.Gerencia, r.Area), r.Cargo
),

DETALLE_GASTO_PERSONAL AS (
    SELECT d.*,
        CAST(ISNULL((d.SUELDOS_Y_SALARIOS + d.ASIGNACION_FAMILIAR) * pr.TOTAL
             / NULLIF(ss.TOTAL + af.TOTAL, 0), 0) AS decimal(14,4)) AS OTROS
    FROM DETALLE_BASE d
    CROSS JOIN TOTAL_PROVEEDORES pr
    CROSS JOIN TOTAL_SUELDOS_Y_SALARIOS ss
    CROSS JOIN TOTAL_ASIGNACION_FAMILIAR af
),

-- Resumen por gerencia
RESUMEN_GASTO_PERSONAL AS (
    SELECT Gerencia AS GERENCIA,
        CAST(SUM(SUELDOS_Y_SALARIOS + GRATIFICACIONES + VACACIONES + ASIGNACION_FAMILIAR
               + REGIMEN_DE_PRESTACIONES_DE_SALUD + SEGUROS_PARTICULARES_DE_SALUD_EPS_Y_OTROS_PARTIC
               + COMPENSACION_POR_TIEMPO_DE_SERVICIO + OTROS) AS decimal(14,4)) AS TOTAL
    FROM DETALLE_GASTO_PERSONAL
    GROUP BY Gerencia
),

TOTAL_GERENTE_GENERAL AS (
    SELECT CAST(ISNULL(SUM(SUELDOS_Y_SALARIOS + GRATIFICACIONES + VACACIONES + ASIGNACION_FAMILIAR
               + REGIMEN_DE_PRESTACIONES_DE_SALUD + SEGUROS_PARTICULARES_DE_SALUD_EPS_Y_OTROS_PARTIC
               + COMPENSACION_POR_TIEMPO_DE_SERVICIO + OTROS), 0) AS decimal(14,4)) AS TOTAL
    FROM DETALLE_GASTO_PERSONAL
    WHERE Cargo = ''GERENTE GENERAL'' AND Gerencia = ''GG''
),

-- Areas de apoyo sin el Gerente General, que se reparte aparte.
TOTAL_AREAS_APOYO AS (
    SELECT CAST(ISNULL((SELECT SUM(TOTAL) FROM RESUMEN_GASTO_PERSONAL
                        WHERE GERENCIA IN (''GAF'', ''GG'', ''GL'', ''OCI'')), 0)
                - (SELECT TOTAL FROM TOTAL_GERENTE_GENERAL) AS decimal(14,4)) AS TOTAL
),

TOTAL_PRECORES_GG AS (
    SELECT CAST(TOTAL * @porcGerenteCore1 / 100 AS decimal(14,4)) AS PRE_CORE_1,
           CAST(TOTAL * @porcGerenteCore2 / 100 AS decimal(14,4)) AS PRE_CORE_2
    FROM TOTAL_GERENTE_GENERAL
),

TOTAL_PRECORES_APOYO AS (
    SELECT CAST(TOTAL * ISNULL(@porcDistGip, 0) / 100 AS decimal(14,4)) AS PRE_CORE_1,
           CAST(TOTAL * ISNULL(@porcDistGo, 0) / 100 AS decimal(14,4)) AS PRE_CORE_2
    FROM TOTAL_AREAS_APOYO
),

TOTAL_GASTO_OPERATIVO AS (
    SELECT CAST(ISNULL(SUM(localamount), 0) AS decimal(14,4)) AS TOTAL
    FROM BD_REP19
    WHERE txtTipoGasto = ''Gasto Operativo''
),

BD_DISTRIBUCION_COMPENSACION AS (
    SELECT c.period, c.DescripcionLocal, c.Proyecto, ISNULL(c.Monto, 0) AS Monto, c.englishname,
           c.txtCategoria, c.Account, c.voucherno, c.vendor, c.invoice
    FROM proceso.TMD_DISTRIBUCION_COMPENSACION c
    WHERE c.idePeriodo = @idePeriodo AND c.flgEstado = 1
),

DISTRIBUCION_COMPENSACION AS (
    SELECT txtCategoria AS FUENTE,
           CONCAT(RIGHT(Proyecto, 6), ''-'', englishname) AS PROYECTO,
           SUM(Monto) AS MONTO,
           CAST(SUM(Monto) * @porcCompensacion / 100 AS decimal(14,4)) AS COMPENSACION
    FROM BD_DISTRIBUCION_COMPENSACION
    GROUP BY txtCategoria, Proyecto, englishname
),

TOTAL_COMPENSACION AS (
    SELECT CAST(ISNULL(SUM(COMPENSACION), 0) AS decimal(14,4)) AS TOTAL
    FROM DISTRIBUCION_COMPENSACION
),

RESUMEN_CORES AS (
    SELECT ''CORE 1'' AS CORE,
        ISNULL((SELECT SUM(TOTAL) FROM RESUMEN_GASTO_PERSONAL WHERE GERENCIA = ''GIP''), 0)
            + (SELECT PRE_CORE_1 FROM TOTAL_PRECORES_GG)
            + (SELECT PRE_CORE_1 FROM TOTAL_PRECORES_APOYO) AS GASTO_PERSONAL,
        (SELECT TOTAL FROM TOTAL_GASTO_OPERATIVO) * ISNULL(@porcDistGip, 0) / 100 AS GASTO_OPERATIVO,
        CAST(0 AS decimal(14,4)) AS COMPENSACION
    UNION ALL
    SELECT ''CORE 2'',
        ISNULL((SELECT SUM(TOTAL) FROM RESUMEN_GASTO_PERSONAL WHERE GERENCIA = ''GO''), 0)
            + (SELECT PRE_CORE_2 FROM TOTAL_PRECORES_GG)
            + (SELECT PRE_CORE_2 FROM TOTAL_PRECORES_APOYO),
        (SELECT TOTAL FROM TOTAL_GASTO_OPERATIVO) * ISNULL(@porcDistGo, 0) / 100,
        (SELECT TOTAL FROM TOTAL_COMPENSACION)
),

RESUMEN_COSTO_LABOR AS (
    SELECT CORE,
           CAST(GASTO_PERSONAL AS decimal(14,4)) AS GASTO_PERSONAL,
           CAST(GASTO_OPERATIVO AS decimal(14,4)) AS GASTO_OPERATIVO,
           CAST(COMPENSACION AS decimal(14,4)) AS COMPENSACION
    FROM RESUMEN_CORES
    -- El periodo sin procesar no debe mostrar dos filas en cero.
    WHERE @idePeriodo IS NOT NULL
),

/* ------------------------------------------------------------------------
   Reparto por proyecto (reportes 8 y 9). Ver la cabecera del script.
   ------------------------------------------------------------------------ */
EMPLEADOS AS (
    SELECT pe.ideEmpleado, pe.nomEmpleado, pe.codDepartamento, pe.codNivel
    FROM registro.TMD_PERIODO_EMPLEADO pe
    WHERE pe.numAnio = @numAnio AND pe.numMes = @numMes AND pe.flgEstado = 1
      AND @idePeriodo IS NOT NULL
),

PROYECTO_FUENTE AS (
    SELECT RIGHT(codProyecto, 6) AS codCorto, codProyecto, codFuente, nomProyecto
    FROM proceso.TMC_PROYECTO_FUENTE
    WHERE flgEstado = 1
),

-- HU-008 CA-02: solo los meses que la jefatura dejo CONFORME.
-- El reparto encadena divisiones: se calcula en float, como el Excel, y se
-- redondea solo al final. Con decimal se truncaban centesimos por proyecto.
HORAS_VALIDADAS AS (
    SELECT r.ideEmpleado, RIGHT(r.codProyecto, 6) AS codCorto, MAX(r.nomProyecto) AS nomProyecto,
           CAST(SUM(r.numHoras) AS float) AS HORAS
    FROM registro.TMD_REGISTRO_HORAMES r
    JOIN registro.VW_REGISTRO_HORAMES_ESTADO v
      ON v.ideEmpleado = r.ideEmpleado AND v.numAnio = r.numAnio AND v.numMes = r.numMes
     AND v.codEstadoValidacion = ''CONFORME''
    WHERE r.numAnio = @numAnio AND r.numMes = @numMes AND r.flgEstado = 1 AND r.numHoras > 0
      AND @idePeriodo IS NOT NULL
    GROUP BY r.ideEmpleado, RIGHT(r.codProyecto, 6)
),

HORAS_EMPLEADO AS (
    SELECT ideEmpleado, SUM(HORAS) AS HORAS_EJECUTADAS
    FROM HORAS_VALIDADAS
    GROUP BY ideEmpleado
),

COSTO_EMPLEADO AS (
    SELECT vendor,
        CAST(SUM(SUELDOS_Y_SALARIOS) AS float) AS SUELDO,
        CAST(SUM(SUELDOS_Y_SALARIOS + GRATIFICACIONES + VACACIONES + ASIGNACION_FAMILIAR
            + REGIMEN_DE_PRESTACIONES_DE_SALUD + SEGUROS_PARTICULARES_DE_SALUD_EPS_Y_OTROS_PARTIC
            + COMPENSACION_POR_TIEMPO_DE_SERVICIO + OTROS) AS float) AS COSTO
    FROM DETALLE_GASTO_PERSONAL
    GROUP BY vendor
),

-- Excel: columnas CI a CL de "HH por proyecto 2".
SUBORDINADOS AS (
    SELECT e.ideEmpleado, e.codDepartamento, h.HORAS_EJECUTADAS,
        CASE WHEN h.HORAS_EJECUTADAS >= @horasReferencia THEN h.HORAS_EJECUTADAS ELSE @horasReferencia END AS HORAS_AJUSTADAS,
        h.HORAS_EJECUTADAS / @horasReferencia * ISNULL(c.SUELDO, 0) AS APORTE
    FROM EMPLEADOS e
    JOIN HORAS_EMPLEADO h ON h.ideEmpleado = e.ideEmpleado
    LEFT JOIN COSTO_EMPLEADO c ON c.vendor = e.ideEmpleado
    WHERE e.codNivel = ''SUBORDINADO'' AND e.codDepartamento IN (''DGO'', ''DIP'', ''DPCM'', ''RRCC'')
),

PESOS AS (
    SELECT s.*,
        -- Sin sueldo registrado en el departamento, todos pesan igual.
        ISNULL(s.APORTE / NULLIF(SUM(s.APORTE) OVER (PARTITION BY s.codDepartamento), 0),
               CAST(1 AS float) / COUNT(*) OVER (PARTITION BY s.codDepartamento)) AS PESO
    FROM SUBORDINADOS s
),

HORAS_DEPARTAMENTO AS (
    SELECT p.codDepartamento, h.codCorto,
        SUM(p.HORAS_AJUSTADAS * h.HORAS / p.HORAS_EJECUTADAS * p.PESO) AS HORAS_PONDERADAS
    FROM PESOS p
    JOIN HORAS_VALIDADAS h ON h.ideEmpleado = p.ideEmpleado
    GROUP BY p.codDepartamento, h.codCorto
),

PROPORCION_DEPARTAMENTO AS (
    SELECT codDepartamento, codCorto,
        HORAS_PONDERADAS / NULLIF(SUM(HORAS_PONDERADAS) OVER (PARTITION BY codDepartamento), 0) AS PROPORCION
    FROM HORAS_DEPARTAMENTO
),

COSTO_DEPARTAMENTO AS (
    SELECT e.codDepartamento, SUM(c.COSTO) AS COSTO
    FROM EMPLEADOS e
    JOIN COSTO_EMPLEADO c ON c.vendor = e.ideEmpleado
    WHERE e.codDepartamento IN (''DGO'', ''DIP'', ''DPCM'', ''RRCC'')
    GROUP BY e.codDepartamento
),

-- Excel: fila "Total GO", mezcla de los departamentos ponderada por su gasto.
PROPORCION_GERENCIA AS (
    SELECT codCorto, PONDERADO / NULLIF(SUM(PONDERADO) OVER (), 0) AS PROPORCION
    FROM (
        SELECT h.codCorto, SUM(h.HORAS_PONDERADAS * cd.COSTO / NULLIF(t.COSTO, 0)) AS PONDERADO
        FROM HORAS_DEPARTAMENTO h
        JOIN COSTO_DEPARTAMENTO cd ON cd.codDepartamento = h.codDepartamento
        CROSS JOIN (SELECT SUM(COSTO) AS COSTO FROM COSTO_DEPARTAMENTO) t
        GROUP BY h.codCorto
    ) x
),

PROPORCION_EMPLEADO AS (
    SELECT e.ideEmpleado, h.codCorto, h.HORAS / he.HORAS_EJECUTADAS AS PROPORCION
    FROM EMPLEADOS e
    JOIN HORAS_EMPLEADO he ON he.ideEmpleado = e.ideEmpleado
    JOIN HORAS_VALIDADAS h ON h.ideEmpleado = e.ideEmpleado
    WHERE e.codNivel = ''SUBORDINADO'' AND e.codDepartamento IN (''DGO'', ''DIP'', ''DPCM'', ''RRCC'')
    UNION ALL
    SELECT e.ideEmpleado, pd.codCorto, pd.PROPORCION
    FROM EMPLEADOS e
    JOIN PROPORCION_DEPARTAMENTO pd ON pd.codDepartamento = e.codDepartamento
    WHERE e.codDepartamento IN (''DGO'', ''DIP'', ''DPCM'', ''RRCC'')
      AND (e.codNivel <> ''SUBORDINADO''
           OR NOT EXISTS (SELECT 1 FROM HORAS_EMPLEADO he WHERE he.ideEmpleado = e.ideEmpleado))
    UNION ALL
    SELECT e.ideEmpleado, pg.codCorto, pg.PROPORCION
    FROM EMPLEADOS e
    CROSS JOIN PROPORCION_GERENCIA pg
    WHERE e.codDepartamento = ''GO''
),

MO_OPERACIONES AS (
    SELECT pe.codCorto, SUM(pe.PROPORCION * c.COSTO) AS MONTO
    FROM PROPORCION_EMPLEADO pe
    JOIN COSTO_EMPLEADO c ON c.vendor = pe.ideEmpleado
    GROUP BY pe.codCorto
),

-- Excel: columna S de "Distribucion MO (Calculo)", promedio simple de los cuatro departamentos.
MO_GERENTE_GENERAL AS (
    SELECT pd.codCorto, SUM(pd.PROPORCION) / 4 * CAST(MAX(gg.PRE_CORE_2) AS float) AS MONTO
    FROM PROPORCION_DEPARTAMENTO pd
    CROSS JOIN TOTAL_PRECORES_GG gg
    GROUP BY pd.codCorto
),

PORCENTAJES_DEPARTAMENTO AS (
    SELECT codDepartamento, PORC_APOYO, PORC_OPERATIVO
    FROM (VALUES (''DGO'',  @porcEscDgo,  @porcGoDgo),
                 (''DIP'',  @porcEscDip,  @porcGoDip),
                 (''DPCM'', @porcEscDpcm, @porcGoDpcm),
                 (''RRCC'', @porcEscRrcc, @porcGoRrcc)) AS d(codDepartamento, PORC_APOYO, PORC_OPERATIVO)
),

MO_AREAS_APOYO AS (
    SELECT pd.codCorto, SUM(pd.PROPORCION * CAST(a.TOTAL AS float) * CAST(pc.PORC_APOYO AS float) / 100) AS MONTO
    FROM PROPORCION_DEPARTAMENTO pd
    JOIN PORCENTAJES_DEPARTAMENTO pc ON pc.codDepartamento = pd.codDepartamento
    CROSS JOIN TOTAL_AREAS_APOYO a
    GROUP BY pd.codCorto
),

GASTO_OPERATIVO_PROYECTO AS (
    SELECT pd.codCorto, SUM(pd.PROPORCION * CAST(g.TOTAL AS float) * CAST(pc.PORC_OPERATIVO AS float) / 100) AS MONTO
    FROM PROPORCION_DEPARTAMENTO pd
    JOIN PORCENTAJES_DEPARTAMENTO pc ON pc.codDepartamento = pd.codDepartamento
    CROSS JOIN TOTAL_GASTO_OPERATIVO g
    GROUP BY pd.codCorto
),

COMPENSACION_PROYECTO AS (
    SELECT RIGHT(Proyecto, 6) AS codCorto, MAX(txtCategoria) AS FUENTE, MAX(englishname) AS nomProyecto,
           CAST(SUM(Monto) * @porcCompensacion / 100 AS float) AS MONTO
    FROM BD_DISTRIBUCION_COMPENSACION
    GROUP BY RIGHT(Proyecto, 6)
),

COSTO_POR_PROYECTO AS (
    SELECT codCorto, SUM(MO) AS MO, SUM(GOP) AS GOP, SUM(COMP) AS COMP
    FROM (
        SELECT codCorto, MONTO AS MO, CAST(0 AS float) AS GOP, CAST(0 AS float) AS COMP FROM MO_OPERACIONES
        UNION ALL SELECT codCorto, MONTO, 0, 0 FROM MO_GERENTE_GENERAL
        UNION ALL SELECT codCorto, MONTO, 0, 0 FROM MO_AREAS_APOYO
        UNION ALL SELECT codCorto, 0, MONTO, 0 FROM GASTO_OPERATIVO_PROYECTO
        UNION ALL SELECT codCorto, 0, 0, MONTO FROM COMPENSACION_PROYECTO
    ) x
    GROUP BY codCorto
),

NOMBRES_HORAS AS (
    SELECT codCorto, MAX(nomProyecto) AS nomProyecto
    FROM HORAS_VALIDADAS
    GROUP BY codCorto
),

TOTAL_COSTO_LABOR AS (
    SELECT COALESCE(pf.codFuente, cp.FUENTE, ''SIN FUENTE'') AS FUENTE,
           COALESCE(pf.codProyecto, c.codCorto) AS CODIGO,
           CONCAT(c.codCorto, ''-'', COALESCE(pf.nomProyecto, cp.nomProyecto, nh.nomProyecto)) AS PROYECTOS,
           CAST(c.MO AS decimal(14,4)) AS MANO_DE_OBRA,
           CAST(c.GOP AS decimal(14,4)) AS GASTO_OPERATIVO,
           CAST(c.COMP AS decimal(14,4)) AS COMPENSACION
    FROM COSTO_POR_PROYECTO c
    LEFT JOIN PROYECTO_FUENTE pf ON pf.codCorto = c.codCorto
    LEFT JOIN COMPENSACION_PROYECTO cp ON cp.codCorto = c.codCorto
    LEFT JOIN NOMBRES_HORAS nh ON nh.codCorto = c.codCorto
    WHERE c.MO <> 0 OR c.GOP <> 0 OR c.COMP <> 0
    UNION ALL
    -- Lo de la Linea Core 1: personal GIP y las partes Core 1 del Gerente General y del apoyo.
    SELECT ''PROINVERSION'', NULL, ''PROINVERSION'', GASTO_PERSONAL, GASTO_OPERATIVO, COMPENSACION
    FROM RESUMEN_COSTO_LABOR
    WHERE CORE = ''CORE 1''
),

-- Pestania 4: horas validadas por colaborador; el SELECT final las pivota por proyecto.
HH_BASE AS (
    SELECT e.codDepartamento AS DEPARTAMENTO, e.codNivel AS NIVEL, e.ideEmpleado AS CODIGO,
           e.nomEmpleado AS COLABORADOR, pu.Cargo AS PUESTO,
           CASE WHEN h.codCorto IS NULL THEN NULL
                ELSE LEFT(CONCAT(h.codCorto, ''-'', COALESCE(pf.nomProyecto, h.nomProyecto)), 120) END AS PROYECTO,
           CASE WHEN pf.codFuente = ''FA'' THEN 1 WHEN pf.codFuente = ''PAR'' THEN 2 WHEN pf.codFuente = ''28E'' THEN 3
                WHEN pf.codFuente = ''TUCARI'' THEN 4 WHEN pf.codFuente = ''TUQUIAR'' THEN 5 ELSE 6 END AS ORDEN_FUENTE,
           CAST(h.HORAS AS decimal(18,2)) AS HORAS
    FROM EMPLEADOS e
    LEFT JOIN HORAS_VALIDADAS h ON h.ideEmpleado = e.ideEmpleado
    LEFT JOIN PROYECTO_FUENTE pf ON pf.codCorto = h.codCorto
    LEFT JOIN (SELECT vendor, MAX(Cargo) AS Cargo FROM BD_REP19 GROUP BY vendor) pu ON pu.vendor = e.ideEmpleado
)
';

    DECLARE @parametros nvarchar(max) = N'@idePeriodo bigint, @numAnio int, @numMes int,
          @porcDistGip decimal(14,4), @porcDistGo decimal(14,4),
          @porcGerenteCore1 decimal(14,4), @porcGerenteCore2 decimal(14,4), @porcCompensacion decimal(14,4),
          @porcEscDgo decimal(14,4), @porcEscDip decimal(14,4), @porcEscDpcm decimal(14,4), @porcEscRrcc decimal(14,4),
          @porcGoDgo decimal(14,4), @porcGoDip decimal(14,4), @porcGoDpcm decimal(14,4), @porcGoRrcc decimal(14,4),
          @horasReferencia decimal(14,4)';

    /* Pestania 4: una columna por proyecto con horas. La lista sale de la misma
       cadena de CTE, asi el nombre de cada columna coincide con el del PIVOT. */
    DECLARE @columnas nvarchar(max), @columnasSelect nvarchar(max);
    IF @cte = 'HH_POR_PROYECTO'
    BEGIN
        DECLARE @sqlColumnas nvarchar(max) = @sql + N'
SELECT @columnas = STRING_AGG(CAST(QUOTENAME(PROYECTO) AS nvarchar(max)), N'','')
                       WITHIN GROUP (ORDER BY ORDEN_FUENTE, PROYECTO),
       @columnasSelect = STRING_AGG(CAST(N''ISNULL('' + QUOTENAME(PROYECTO) + N'', 0) AS '' + QUOTENAME(PROYECTO) AS nvarchar(max)), N'','')
                       WITHIN GROUP (ORDER BY ORDEN_FUENTE, PROYECTO)
FROM (SELECT DISTINCT PROYECTO, ORDEN_FUENTE FROM HH_BASE WHERE PROYECTO IS NOT NULL) p;';

        -- EXEC no admite expresiones como argumento: la firma va armada en una variable.
        DECLARE @parametrosColumnas nvarchar(max) =
            @parametros + N', @columnas nvarchar(max) OUTPUT, @columnasSelect nvarchar(max) OUTPUT';

        EXEC sp_executesql @sqlColumnas, @parametrosColumnas,
            @idePeriodo = @idePeriodo, @numAnio = @numAnio, @numMes = @numMes,
            @porcDistGip = @porcDistGip, @porcDistGo = @porcDistGo,
            @porcGerenteCore1 = @porcGerenteCore1, @porcGerenteCore2 = @porcGerenteCore2,
            @porcCompensacion = @porcCompensacion,
            @porcEscDgo = @porcEscDgo, @porcEscDip = @porcEscDip, @porcEscDpcm = @porcEscDpcm, @porcEscRrcc = @porcEscRrcc,
            @porcGoDgo = @porcGoDgo, @porcGoDip = @porcGoDip, @porcGoDpcm = @porcGoDpcm, @porcGoRrcc = @porcGoRrcc,
            @horasReferencia = @horasReferencia,
            @columnas = @columnas OUTPUT, @columnasSelect = @columnasSelect OUTPUT;
    END

    SET @sql = @sql + N',
HH_POR_PROYECTO AS (
    SELECT DEPARTAMENTO, NIVEL, CODIGO, COLABORADOR, PUESTO'
        + CASE WHEN @columnas IS NULL
               -- Sin horas validadas: la lista de colaboradores, sin columnas de proyecto.
               THEN N' FROM (SELECT DISTINCT DEPARTAMENTO, NIVEL, CODIGO, COLABORADOR, PUESTO FROM HH_BASE) b'
               ELSE N', ' + @columnasSelect
                    + N' FROM (SELECT DEPARTAMENTO, NIVEL, CODIGO, COLABORADOR, PUESTO, PROYECTO, HORAS FROM HH_BASE) b'
                    + N' PIVOT (SUM(HORAS) FOR PROYECTO IN (' + @columnas + N')) pv'
          END
        + N'
)
';

    -- SQL Server solo evalua los CTE que usa el SELECT final, asi que pedir
    -- un reporte no calcula los demas.
    SET @sql = @sql + N'SELECT * FROM ' + QUOTENAME(@cte) + N' ORDER BY ' + @orden + N';';

    EXEC sp_executesql @sql, @parametros,
        @idePeriodo = @idePeriodo, @numAnio = @numAnio, @numMes = @numMes,
        @porcDistGip = @porcDistGip, @porcDistGo = @porcDistGo,
        @porcGerenteCore1 = @porcGerenteCore1, @porcGerenteCore2 = @porcGerenteCore2,
        @porcCompensacion = @porcCompensacion,
        @porcEscDgo = @porcEscDgo, @porcEscDip = @porcEscDip, @porcEscDpcm = @porcEscDpcm, @porcEscRrcc = @porcEscRrcc,
        @porcGoDgo = @porcGoDgo, @porcGoDip = @porcGoDip, @porcGoDpcm = @porcGoDpcm, @porcGoRrcc = @porcGoRrcc,
        @horasReferencia = @horasReferencia;
END
GO
