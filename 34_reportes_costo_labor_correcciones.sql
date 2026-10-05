/* =========================================================================
   34 - Reportes del costo labor con las correcciones del 27/09

   Rehace proceso.usp_Reporte_CostoLabor (script 29) con:

   1. Filtros movidos: BD_REP19 y BD_DISTRIBUCION_COMPENSACION leen las vistas
      del script 32, que aplican los filtros que antes tenia la extraccion.

   2. HH por proyecto: las filas son los trabajadores del gasto de personal del
      periodo (Gerencia de Operaciones, o con su cargo en
      proceso.TMC_CARGO_NIVEL) y el cargo define departamento y nivel. Las
      columnas son todos los proyectos de la distribucion de compensacion y
      solo cuentan las horas en esos proyectos, tambien para el reparto.

   3. INCONSISTENCIAS: horas registradas en proyectos que no estan en la
      distribucion de compensacion de SPRING.

   4. TOTAL_COSTO_LABOR: lo del CORE 2 que no llega a ningun proyecto sale en
      la fila SIN DISTRIBUIR. Antes se perdia y la mano de obra por proyecto
      salia en cero, por eso la compensacion y el total coincidian.

   5. Proyectos por codigo completo: el script 29 cruzaba horas y
      compensacion por los ultimos seis digitos, y en afemst hay proyectos
      distintos que los comparten (000000000019 5 RELAVERAS y 002026000019
      Lodocretos). Un codigo de 6 digitos de periodos anteriores se completa
      con seis ceros. En pantalla se sigue mostrando el codigo corto, salvo
      que dos proyectos de la lista lo compartan.

   6. Gasto no recuperable (script 33): RESUMEN_GASTO_PERSONAL tiene MONTO
      (recuperable), una columna por grupo y TOTAL. Los Core y el reparto por
      proyecto usan solo lo recuperable.

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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
                                         + N'WHEN ''TUQUIAR'' THEN 5 WHEN ''PROINVERSION'' THEN 7 WHEN ''SIN DISTRIBUIR'' THEN 8 ELSE 6 END, PROYECTOS'),
        ('INCONSISTENCIAS',              N'COLABORADOR, PROYECTO');

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
    -- Correcciones 27/09: los filtros que antes aplicaba la extraccion.
    FROM proceso.VW_GASTO_PERSONAL_REPORTE g
    WHERE g.idePeriodo = @idePeriodo
),

RESUMEN_GRAL_GASTO_PERSONAL AS (
    SELECT txtTipoGasto, txtLocalName, account, SUM(localamount) AS TOTAL
    FROM BD_REP19
    GROUP BY txtTipoGasto, txtLocalName, account
),

-- Correcciones 27/09: personal de los grupos de gasto no recuperable del
-- periodo (script 33). Su gasto se muestra aparte y no se reparte por proyecto.
GRUPOS_PERSONA AS (
    SELECT gp.idePersona, MAX(g.nomGrupo) AS nomGrupo
    FROM proceso.TMD_GRUPO_NO_RECUPERABLE_PERSONA gp
    JOIN proceso.TMC_GRUPO_NO_RECUPERABLE g
      ON g.ideGrupoNoRecuperable = gp.ideGrupoNoRecuperable AND g.flgEstado = 1
    WHERE g.numAnio = @numAnio AND g.numMes = @numMes AND gp.flgEstado = 1
    GROUP BY gp.idePersona
),

-- Proveedores sin area: su gasto se reparte entre todos como OTROS. Si el
-- contador los puso en un grupo de gasto no recuperable, quedan fuera.
TOTAL_PROVEEDORES AS (
    SELECT CAST(ISNULL(SUM(localamount), 0) AS decimal(14,4)) AS TOTAL
    FROM BD_REP19
    WHERE txtTipoGasto = ''Gasto de Personal'' AND ISNULL(Area, '''') = ''''
      AND vendor NOT IN (SELECT idePersona FROM GRUPOS_PERSONA)
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

DETALLE_CON_GRUPO AS (
    SELECT d.vendor, d.Gerencia, gp.nomGrupo,
        CAST(d.SUELDOS_Y_SALARIOS + d.GRATIFICACIONES + d.VACACIONES + d.ASIGNACION_FAMILIAR
               + d.REGIMEN_DE_PRESTACIONES_DE_SALUD + d.SEGUROS_PARTICULARES_DE_SALUD_EPS_Y_OTROS_PARTIC
               + d.COMPENSACION_POR_TIEMPO_DE_SERVICIO + d.OTROS AS decimal(14,4)) AS TOTAL
    FROM DETALLE_GASTO_PERSONAL d
    LEFT JOIN GRUPOS_PERSONA gp ON gp.idePersona = d.vendor
),

-- Resumen por gerencia. MONTO es lo recuperable, que es lo que se reparte;
-- TOTAL suma ademas los grupos de gasto no recuperable. El reporte
-- RESUMEN_GASTO_PERSONAL lo muestra con una columna por grupo.
RESUMEN_GERENCIA AS (
    SELECT Gerencia AS GERENCIA,
        CAST(SUM(CASE WHEN nomGrupo IS NULL THEN TOTAL ELSE 0 END) AS decimal(14,4)) AS MONTO,
        CAST(SUM(TOTAL) AS decimal(14,4)) AS TOTAL
    FROM DETALLE_CON_GRUPO
    GROUP BY Gerencia
),

TOTAL_GERENTE_GENERAL AS (
    SELECT CAST(ISNULL(SUM(SUELDOS_Y_SALARIOS + GRATIFICACIONES + VACACIONES + ASIGNACION_FAMILIAR
               + REGIMEN_DE_PRESTACIONES_DE_SALUD + SEGUROS_PARTICULARES_DE_SALUD_EPS_Y_OTROS_PARTIC
               + COMPENSACION_POR_TIEMPO_DE_SERVICIO + OTROS), 0) AS decimal(14,4)) AS TOTAL
    FROM DETALLE_GASTO_PERSONAL
    WHERE Cargo = ''GERENTE GENERAL'' AND Gerencia = ''GG''
      AND vendor NOT IN (SELECT idePersona FROM GRUPOS_PERSONA)
),

-- Areas de apoyo sin el Gerente General, que se reparte aparte.
TOTAL_AREAS_APOYO AS (
    SELECT CAST(ISNULL((SELECT SUM(MONTO) FROM RESUMEN_GERENCIA
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
    FROM proceso.VW_DISTRIBUCION_COMPENSACION_REPORTE c
    WHERE c.idePeriodo = @idePeriodo
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
        ISNULL((SELECT SUM(MONTO) FROM RESUMEN_GERENCIA WHERE GERENCIA = ''GIP''), 0)
            + (SELECT PRE_CORE_1 FROM TOTAL_PRECORES_GG)
            + (SELECT PRE_CORE_1 FROM TOTAL_PRECORES_APOYO) AS GASTO_PERSONAL,
        (SELECT TOTAL FROM TOTAL_GASTO_OPERATIVO) * ISNULL(@porcDistGip, 0) / 100 AS GASTO_OPERATIVO,
        CAST(0 AS decimal(14,4)) AS COMPENSACION
    UNION ALL
    SELECT ''CORE 2'',
        ISNULL((SELECT SUM(MONTO) FROM RESUMEN_GERENCIA WHERE GERENCIA = ''GO''), 0)
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
-- Correcciones 27/09: los colaboradores son los del gasto de personal del
-- periodo, y el cargo define departamento y nivel con proceso.ufn_ClasificarCargo
-- (script 32). Quien no clasifica no entra al HH por proyecto.
PERSONAL_PERIODO AS (
    SELECT vendor AS ideEmpleado, MAX(txtNombreCompleto) AS nomEmpleado,
           MAX(Area) AS Area, MAX(Departamento) AS Departamento, MAX(Cargo) AS Cargo
    FROM BD_REP19
    WHERE txtTipoGasto = ''Gasto de Personal'' AND vendor IS NOT NULL
    GROUP BY vendor
),

EMPLEADOS AS (
    SELECT p.ideEmpleado, p.nomEmpleado, p.Cargo, c.codDepartamento, c.codNivel
    FROM PERSONAL_PERIODO p
    CROSS APPLY proceso.ufn_ClasificarCargo(p.Area, p.Departamento, p.Cargo) c
    WHERE @idePeriodo IS NOT NULL
),

PROYECTO_FUENTE AS (
    SELECT codProyecto AS codClave, codProyecto, codFuente, nomProyecto
    FROM proceso.TMC_PROYECTO_FUENTE
    WHERE flgEstado = 1
),

-- Correcciones 27/09: las columnas del HH por proyecto son los proyectos de la
-- distribucion de compensacion, tengan o no horas.
PROYECTOS_COMPENSACION AS (
    SELECT Proyecto AS codClave, MAX(englishname) AS nomProyecto, MAX(txtCategoria) AS FUENTE
    FROM BD_DISTRIBUCION_COMPENSACION
    WHERE Proyecto IS NOT NULL
    GROUP BY Proyecto
),

PROYECTOS_HH AS (
    SELECT pc.codClave,
           -- El codigo corto, como en el Excel; el completo si otro proyecto de la
           -- lista comparte los ultimos seis digitos, para que no se confundan.
           LEFT(CONCAT(CASE WHEN COUNT(*) OVER (PARTITION BY RIGHT(pc.codClave, 6)) > 1
                            THEN pc.codClave ELSE RIGHT(pc.codClave, 6) END,
                       ''-'', COALESCE(pf.nomProyecto, pc.nomProyecto)), 120) AS PROYECTO,
           CASE COALESCE(pf.codFuente, pc.FUENTE) WHEN ''FA'' THEN 1 WHEN ''PAR'' THEN 2 WHEN ''28E'' THEN 3
                WHEN ''TUCARI'' THEN 4 WHEN ''TUQUIAR'' THEN 5 ELSE 6 END AS ORDEN_FUENTE
    FROM PROYECTOS_COMPENSACION pc
    LEFT JOIN PROYECTO_FUENTE pf ON pf.codClave = pc.codClave
),

-- HU-008 CA-02: solo los meses que la jefatura dejo CONFORME. Desde el 27/09,
-- solo en proyectos de la distribucion de compensacion; el resto sale en
-- INCONSISTENCIAS.
-- El reparto encadena divisiones: se calcula en float, como el Excel, y se
-- redondea solo al final. Con decimal se truncaban centesimos por proyecto.
HORAS_VALIDADAS AS (
    SELECT r.ideEmpleado, CASE WHEN LEN(r.codProyecto) = 6 THEN CONCAT(''000000'', r.codProyecto) ELSE r.codProyecto END AS codClave, MAX(r.nomProyecto) AS nomProyecto,
           CAST(SUM(r.numHoras) AS float) AS HORAS
    FROM registro.TMD_REGISTRO_HORAMES r
    JOIN registro.VW_REGISTRO_HORAMES_ESTADO v
      ON v.ideEmpleado = r.ideEmpleado AND v.numAnio = r.numAnio AND v.numMes = r.numMes
     AND v.codEstadoValidacion = ''CONFORME''
    WHERE r.numAnio = @numAnio AND r.numMes = @numMes AND r.flgEstado = 1 AND r.numHoras > 0
      AND @idePeriodo IS NOT NULL
      AND CASE WHEN LEN(r.codProyecto) = 6 THEN CONCAT(''000000'', r.codProyecto) ELSE r.codProyecto END IN (SELECT codClave FROM PROYECTOS_COMPENSACION)
    GROUP BY r.ideEmpleado, CASE WHEN LEN(r.codProyecto) = 6 THEN CONCAT(''000000'', r.codProyecto) ELSE r.codProyecto END
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
    -- El gasto no recuperable no se reparte por proyecto.
    WHERE vendor NOT IN (SELECT idePersona FROM GRUPOS_PERSONA)
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
    SELECT p.codDepartamento, h.codClave,
        SUM(p.HORAS_AJUSTADAS * h.HORAS / p.HORAS_EJECUTADAS * p.PESO) AS HORAS_PONDERADAS
    FROM PESOS p
    JOIN HORAS_VALIDADAS h ON h.ideEmpleado = p.ideEmpleado
    GROUP BY p.codDepartamento, h.codClave
),

PROPORCION_DEPARTAMENTO AS (
    SELECT codDepartamento, codClave,
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
    SELECT codClave, PONDERADO / NULLIF(SUM(PONDERADO) OVER (), 0) AS PROPORCION
    FROM (
        SELECT h.codClave, SUM(h.HORAS_PONDERADAS * cd.COSTO / NULLIF(t.COSTO, 0)) AS PONDERADO
        FROM HORAS_DEPARTAMENTO h
        JOIN COSTO_DEPARTAMENTO cd ON cd.codDepartamento = h.codDepartamento
        CROSS JOIN (SELECT SUM(COSTO) AS COSTO FROM COSTO_DEPARTAMENTO) t
        GROUP BY h.codClave
    ) x
),

PROPORCION_EMPLEADO AS (
    SELECT e.ideEmpleado, h.codClave, h.HORAS / he.HORAS_EJECUTADAS AS PROPORCION
    FROM EMPLEADOS e
    JOIN HORAS_EMPLEADO he ON he.ideEmpleado = e.ideEmpleado
    JOIN HORAS_VALIDADAS h ON h.ideEmpleado = e.ideEmpleado
    WHERE e.codNivel = ''SUBORDINADO'' AND e.codDepartamento IN (''DGO'', ''DIP'', ''DPCM'', ''RRCC'')
    UNION ALL
    SELECT e.ideEmpleado, pd.codClave, pd.PROPORCION
    FROM EMPLEADOS e
    JOIN PROPORCION_DEPARTAMENTO pd ON pd.codDepartamento = e.codDepartamento
    WHERE e.codDepartamento IN (''DGO'', ''DIP'', ''DPCM'', ''RRCC'')
      AND (e.codNivel <> ''SUBORDINADO''
           OR NOT EXISTS (SELECT 1 FROM HORAS_EMPLEADO he WHERE he.ideEmpleado = e.ideEmpleado))
    UNION ALL
    SELECT e.ideEmpleado, pg.codClave, pg.PROPORCION
    FROM EMPLEADOS e
    CROSS JOIN PROPORCION_GERENCIA pg
    WHERE e.codDepartamento = ''GO''
),

MO_OPERACIONES AS (
    SELECT pe.codClave, SUM(pe.PROPORCION * c.COSTO) AS MONTO
    FROM PROPORCION_EMPLEADO pe
    JOIN COSTO_EMPLEADO c ON c.vendor = pe.ideEmpleado
    GROUP BY pe.codClave
),

-- Excel: columna S de "Distribucion MO (Calculo)", promedio simple de los cuatro departamentos.
MO_GERENTE_GENERAL AS (
    SELECT pd.codClave, SUM(pd.PROPORCION) / 4 * CAST(MAX(gg.PRE_CORE_2) AS float) AS MONTO
    FROM PROPORCION_DEPARTAMENTO pd
    CROSS JOIN TOTAL_PRECORES_GG gg
    GROUP BY pd.codClave
),

PORCENTAJES_DEPARTAMENTO AS (
    SELECT codDepartamento, PORC_APOYO, PORC_OPERATIVO
    FROM (VALUES (''DGO'',  @porcEscDgo,  @porcGoDgo),
                 (''DIP'',  @porcEscDip,  @porcGoDip),
                 (''DPCM'', @porcEscDpcm, @porcGoDpcm),
                 (''RRCC'', @porcEscRrcc, @porcGoRrcc)) AS d(codDepartamento, PORC_APOYO, PORC_OPERATIVO)
),

MO_AREAS_APOYO AS (
    SELECT pd.codClave, SUM(pd.PROPORCION * CAST(a.TOTAL AS float) * CAST(pc.PORC_APOYO AS float) / 100) AS MONTO
    FROM PROPORCION_DEPARTAMENTO pd
    JOIN PORCENTAJES_DEPARTAMENTO pc ON pc.codDepartamento = pd.codDepartamento
    CROSS JOIN TOTAL_AREAS_APOYO a
    GROUP BY pd.codClave
),

GASTO_OPERATIVO_PROYECTO AS (
    SELECT pd.codClave, SUM(pd.PROPORCION * CAST(g.TOTAL AS float) * CAST(pc.PORC_OPERATIVO AS float) / 100) AS MONTO
    FROM PROPORCION_DEPARTAMENTO pd
    JOIN PORCENTAJES_DEPARTAMENTO pc ON pc.codDepartamento = pd.codDepartamento
    CROSS JOIN TOTAL_GASTO_OPERATIVO g
    GROUP BY pd.codClave
),

COMPENSACION_PROYECTO AS (
    SELECT Proyecto AS codClave, MAX(txtCategoria) AS FUENTE, MAX(englishname) AS nomProyecto,
           CAST(SUM(Monto) * @porcCompensacion / 100 AS float) AS MONTO
    FROM BD_DISTRIBUCION_COMPENSACION
    GROUP BY Proyecto
),

COSTO_POR_PROYECTO AS (
    SELECT codClave, SUM(MO) AS MO, SUM(GOP) AS GOP, SUM(COMP) AS COMP
    FROM (
        SELECT codClave, MONTO AS MO, CAST(0 AS float) AS GOP, CAST(0 AS float) AS COMP FROM MO_OPERACIONES
        UNION ALL SELECT codClave, MONTO, 0, 0 FROM MO_GERENTE_GENERAL
        UNION ALL SELECT codClave, MONTO, 0, 0 FROM MO_AREAS_APOYO
        UNION ALL SELECT codClave, 0, MONTO, 0 FROM GASTO_OPERATIVO_PROYECTO
        UNION ALL SELECT codClave, 0, 0, MONTO FROM COMPENSACION_PROYECTO
    ) x
    GROUP BY codClave
),

NOMBRES_HORAS AS (
    SELECT codClave, MAX(nomProyecto) AS nomProyecto
    FROM HORAS_VALIDADAS
    GROUP BY codClave
),

-- Lo del CORE 2 que no llego a ningun proyecto: departamentos sin horas
-- validadas o personal sin departamento. Antes se perdia sin aviso y la mano de
-- obra salia en cero (observacion del 27/09: compensacion igual al total).
SIN_DISTRIBUIR AS (
    SELECT CAST(r.GASTO_PERSONAL - ISNULL(t.MO, 0) AS decimal(14,4)) AS MO,
           CAST(r.GASTO_OPERATIVO - ISNULL(t.GOP, 0) AS decimal(14,4)) AS GOP
    FROM RESUMEN_COSTO_LABOR r
    CROSS JOIN (SELECT SUM(MO) AS MO, SUM(GOP) AS GOP FROM COSTO_POR_PROYECTO) t
    WHERE r.CORE = ''CORE 2''
),

TOTAL_COSTO_LABOR AS (
    SELECT COALESCE(pf.codFuente, cp.FUENTE, ''SIN FUENTE'') AS FUENTE,
           c.codClave AS CODIGO,
           CONCAT(CASE WHEN COUNT(*) OVER (PARTITION BY RIGHT(c.codClave, 6)) > 1
                       THEN c.codClave ELSE RIGHT(c.codClave, 6) END,
                  ''-'', COALESCE(pf.nomProyecto, cp.nomProyecto, nh.nomProyecto)) AS PROYECTOS,
           CAST(c.MO AS decimal(14,4)) AS MANO_DE_OBRA,
           CAST(c.GOP AS decimal(14,4)) AS GASTO_OPERATIVO,
           CAST(c.COMP AS decimal(14,4)) AS COMPENSACION
    FROM COSTO_POR_PROYECTO c
    LEFT JOIN PROYECTO_FUENTE pf ON pf.codClave = c.codClave
    LEFT JOIN COMPENSACION_PROYECTO cp ON cp.codClave = c.codClave
    LEFT JOIN NOMBRES_HORAS nh ON nh.codClave = c.codClave
    WHERE c.MO <> 0 OR c.GOP <> 0 OR c.COMP <> 0
    UNION ALL
    -- Lo de la Linea Core 1: personal GIP y las partes Core 1 del Gerente General y del apoyo.
    SELECT ''PROINVERSION'', NULL, ''PROINVERSION'', GASTO_PERSONAL, GASTO_OPERATIVO, COMPENSACION
    FROM RESUMEN_COSTO_LABOR
    WHERE CORE = ''CORE 1''
    UNION ALL
    SELECT ''SIN DISTRIBUIR'', NULL, ''SIN DISTRIBUIR (FALTAN HORAS VALIDADAS)'', MO, GOP, CAST(0 AS decimal(14,4))
    FROM SIN_DISTRIBUIR
    WHERE ABS(MO) >= 0.01 OR ABS(GOP) >= 0.01
),

-- Pestania 4: horas validadas por colaborador; el SELECT final las pivota por proyecto.
HH_BASE AS (
    SELECT e.codDepartamento AS DEPARTAMENTO, e.codNivel AS NIVEL, e.ideEmpleado AS CODIGO,
           e.nomEmpleado AS COLABORADOR, e.Cargo AS PUESTO,
           ph.PROYECTO, ph.ORDEN_FUENTE,
           CAST(h.HORAS AS decimal(18,2)) AS HORAS
    FROM EMPLEADOS e
    LEFT JOIN HORAS_VALIDADAS h ON h.ideEmpleado = e.ideEmpleado
    LEFT JOIN PROYECTOS_HH ph ON ph.codClave = h.codClave
),

-- Correcciones 27/09: horas registradas en proyectos que no estan en la
-- distribucion de compensacion de SPRING. Se listan todas, validadas o no,
-- para corregirlas antes de aprobar el periodo.
INCONSISTENCIAS AS (
    SELECT r.ideEmpleado AS CODIGO, MAX(r.nomEmpleado) AS COLABORADOR,
           r.codProyecto AS PROYECTO, MAX(r.nomProyecto) AS NOMBRE_PROYECTO,
           ISNULL(MAX(v.codEstadoValidacion), ''PENDIENTE'') AS ESTADO,
           CAST(SUM(r.numHoras) AS decimal(18,2)) AS HORAS
    FROM registro.TMD_REGISTRO_HORAMES r
    LEFT JOIN registro.VW_REGISTRO_HORAMES_ESTADO v
           ON v.ideEmpleado = r.ideEmpleado AND v.numAnio = r.numAnio AND v.numMes = r.numMes
    WHERE r.numAnio = @numAnio AND r.numMes = @numMes AND r.flgEstado = 1 AND r.numHoras > 0
      AND @idePeriodo IS NOT NULL
      AND CASE WHEN LEN(r.codProyecto) = 6 THEN CONCAT(''000000'', r.codProyecto) ELSE r.codProyecto END NOT IN (SELECT codClave FROM PROYECTOS_COMPENSACION)
    GROUP BY r.ideEmpleado, r.codProyecto
)
';

    DECLARE @parametros nvarchar(max) = N'@idePeriodo bigint, @numAnio int, @numMes int,
          @porcDistGip decimal(14,4), @porcDistGo decimal(14,4),
          @porcGerenteCore1 decimal(14,4), @porcGerenteCore2 decimal(14,4), @porcCompensacion decimal(14,4),
          @porcEscDgo decimal(14,4), @porcEscDip decimal(14,4), @porcEscDpcm decimal(14,4), @porcEscRrcc decimal(14,4),
          @porcGoDgo decimal(14,4), @porcGoDip decimal(14,4), @porcGoDpcm decimal(14,4), @porcGoRrcc decimal(14,4),
          @horasReferencia decimal(14,4)';

    /* Pestania 4: una columna por proyecto de la distribucion de compensacion
       (correcciones 27/09). La lista sale de la misma cadena de CTE, asi el
       nombre de cada columna coincide con el del PIVOT. */
    DECLARE @columnas nvarchar(max), @columnasSelect nvarchar(max);
    IF @cte = 'HH_POR_PROYECTO'
    BEGIN
        DECLARE @sqlColumnas nvarchar(max) = @sql + N'
SELECT @columnas = STRING_AGG(CAST(QUOTENAME(PROYECTO) AS nvarchar(max)), N'','')
                       WITHIN GROUP (ORDER BY ORDEN_FUENTE, PROYECTO),
       @columnasSelect = STRING_AGG(CAST(N''ISNULL('' + QUOTENAME(PROYECTO) + N'', 0) AS '' + QUOTENAME(PROYECTO) AS nvarchar(max)), N'','')
                       WITHIN GROUP (ORDER BY ORDEN_FUENTE, PROYECTO)
FROM PROYECTOS_HH p;';

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

    /* Resumen por gerencia: una columna por grupo de gasto no recuperable del
       periodo, aunque no tenga monto (correcciones 27/09). */
    DECLARE @grupos nvarchar(max), @gruposSelect nvarchar(max);
    IF @cte = 'RESUMEN_GASTO_PERSONAL'
        SELECT @grupos = STRING_AGG(CAST(QUOTENAME(nomGrupo) AS nvarchar(max)), N',')
                             WITHIN GROUP (ORDER BY nomGrupo),
               @gruposSelect = STRING_AGG(CAST(N'ISNULL(g.' + QUOTENAME(nomGrupo) + N', 0) AS ' + QUOTENAME(nomGrupo) AS nvarchar(max)), N', ')
                             WITHIN GROUP (ORDER BY nomGrupo)
        FROM proceso.TMC_GRUPO_NO_RECUPERABLE
        WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1;

    SET @sql = @sql + N',
HH_POR_PROYECTO AS (
    SELECT DEPARTAMENTO, NIVEL, CODIGO, COLABORADOR, PUESTO'
        + CASE WHEN @columnas IS NULL
               -- Sin proyectos en la compensacion: la lista de colaboradores, sin columnas.
               THEN N' FROM (SELECT DISTINCT DEPARTAMENTO, NIVEL, CODIGO, COLABORADOR, PUESTO FROM HH_BASE) b'
               ELSE N', ' + @columnasSelect
                    + N' FROM (SELECT DEPARTAMENTO, NIVEL, CODIGO, COLABORADOR, PUESTO, PROYECTO, HORAS FROM HH_BASE) b'
                    + N' PIVOT (SUM(HORAS) FOR PROYECTO IN (' + @columnas + N')) pv'
          END
        + N'
),

RESUMEN_GASTO_PERSONAL AS (
    SELECT rg.GERENCIA, rg.MONTO, '
        + ISNULL(@gruposSelect + N', ', N'')
        + N'rg.TOTAL
    FROM RESUMEN_GERENCIA rg'
        + CASE WHEN @grupos IS NULL THEN N''
               ELSE N'
    LEFT JOIN (SELECT * FROM (SELECT Gerencia AS _GERENCIA, nomGrupo AS _GRUPO, TOTAL AS _TOTAL
                              FROM DETALLE_CON_GRUPO WHERE nomGrupo IS NOT NULL) d
               PIVOT (SUM(_TOTAL) FOR _GRUPO IN (' + @grupos + N')) pv) g
           -- Personal sin area: gerencia nula, que tambien debe cruzar.
           ON g._GERENCIA = rg.GERENCIA OR (g._GERENCIA IS NULL AND rg.GERENCIA IS NULL)'
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
