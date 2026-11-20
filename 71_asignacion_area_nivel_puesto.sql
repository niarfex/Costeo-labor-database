/* =========================================================================
   71 - Asignacion de personal: departamento, nivel, puesto y remuneracion

   Observacion 6: SPRING no guarda el historico de cargos. Quien era gestor
   de obras de la DGO en el periodo y hoy es jefe de la DPCM sale como jefe
   en el HH por proyecto. La asignacion del Contador (script 47) registra
   ahora, ademas del area, el departamento (DGO, DIP, DPCM, RRCC, GO), el
   nivel (JEFE, ADMINISTRATIVO, SUBORDINADO), el puesto y la remuneracion
   basica del periodo. Todos opcionales.

   Observacion 7: RELACION_GO lista a todos los de HH_POR_PROYECTO, tengan
   o no horas, y con lo de la asignacion cuando existe.

   1. proceso.TMD_ASIGNACION_AREA: columnas codDepartamento, codNivel,
      txtPuesto y numRemuneracionBasica (nulas).
   2. Listar, Guardar y Replicar (version del script 47) con las columnas
      nuevas. Guardar las recibe al final y opcionales. Departamento y nivel
      solo valen con el area GERENCIA DE OPERACIONES: fuera de ella la
      persona no entra al HH por proyecto (proceso.ufn_ClasificarCargo) y su
      gasto se contaria dos veces.
   3. proceso.usp_Reporte_CostoLabor, desde la version del script 70:
      - EMPLEADOS: departamento y nivel de la asignacion; si no los trae, los
        de proceso.ufn_ClasificarCargo con el puesto asignado (o el cargo de
        SPRING). El puesto asignado reemplaza al cargo. Con eso cambian
        HH_POR_PROYECTO, COEFICIENTES, el costo labor y las inconsistencias.
      - RELACION_GO: el mismo personal que HH_POR_PROYECTO, sin exigir horas,
        sueldo ni documento de 8 caracteres. De SPRING solo el documento y el
        sueldo actual; la remuneracion de la asignacion manda sobre el sueldo.

   Errores nuevos:
     50155  departamento no valido
     50156  nivel no valido
     50157  remuneracion negativa
     50158  departamento o nivel con un area que no es la Gerencia de Operaciones

   Requiere los scripts 47 y 70.

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF OBJECT_ID('proceso.TMD_ASIGNACION_AREA') IS NULL
   OR COL_LENGTH('proceso.VW_GASTO_PERSONAL_REPORTE', 'AreaSpring') IS NULL
    THROW 50154, 'Faltan objetos previos: ejecute antes los scripts 47 y 70.', 1;
GO

/* -------------------------------------------------------------------------
   1. Columnas nuevas de la asignacion
   ------------------------------------------------------------------------- */

IF COL_LENGTH('proceso.TMD_ASIGNACION_AREA', 'codDepartamento') IS NULL
    ALTER TABLE proceso.TMD_ASIGNACION_AREA ADD codDepartamento varchar(10) NULL;
IF COL_LENGTH('proceso.TMD_ASIGNACION_AREA', 'codNivel') IS NULL
    ALTER TABLE proceso.TMD_ASIGNACION_AREA ADD codNivel varchar(20) NULL;
IF COL_LENGTH('proceso.TMD_ASIGNACION_AREA', 'txtPuesto') IS NULL
    ALTER TABLE proceso.TMD_ASIGNACION_AREA ADD txtPuesto varchar(200) NULL;
IF COL_LENGTH('proceso.TMD_ASIGNACION_AREA', 'numRemuneracionBasica') IS NULL
    ALTER TABLE proceso.TMD_ASIGNACION_AREA ADD numRemuneracionBasica decimal(18,2) NULL;
GO

-- Los mismos codigos que proceso.ufn_ClasificarCargo. GERENTE no se ofrece:
-- en el calculo se trata igual que ADMINISTRATIVO.
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_TMD_ASIGNACION_AREA_DEPARTAMENTO')
    ALTER TABLE proceso.TMD_ASIGNACION_AREA ADD CONSTRAINT CK_TMD_ASIGNACION_AREA_DEPARTAMENTO
        CHECK (codDepartamento IN ('DGO', 'DIP', 'DPCM', 'RRCC', 'GO'));
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_TMD_ASIGNACION_AREA_NIVEL')
    ALTER TABLE proceso.TMD_ASIGNACION_AREA ADD CONSTRAINT CK_TMD_ASIGNACION_AREA_NIVEL
        CHECK (codNivel IN ('JEFE', 'ADMINISTRATIVO', 'SUBORDINADO'));
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_TMD_ASIGNACION_AREA_REMUNERACION')
    ALTER TABLE proceso.TMD_ASIGNACION_AREA ADD CONSTRAINT CK_TMD_ASIGNACION_AREA_REMUNERACION
        CHECK (numRemuneracionBasica >= 0);
GO

/* -------------------------------------------------------------------------
   2. Listado del periodo
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_AsignacionArea_Listar
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
                     THEN 1 ELSE 0 END AS bit) AS flgCerrado;

    SELECT a.ideAsignacionArea, a.idePersona, a.nomPersona, a.txtDocumento, a.codArea, a.nomArea, a.txtMotivo,
           a.codDepartamento, a.codNivel, a.txtPuesto, a.numRemuneracionBasica
    FROM proceso.TMD_ASIGNACION_AREA a
    WHERE a.numAnio = @numAnio AND a.numMes = @numMes AND a.flgEstado = 1
    ORDER BY a.nomPersona;
END
GO

/* -------------------------------------------------------------------------
   3. Registrar o editar

   Con @ideAsignacionArea nulo es un alta en el periodo indicado; si no, se
   edita (area, motivo y los datos del script 71) y el periodo y la persona
   son los del registro. En la edicion, un dato nuevo que no llega se borra.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_AsignacionArea_Guardar
    @ideAsignacionArea     bigint = NULL,
    @numAnio               int,
    @numMes                int,
    @idePersona            bigint,
    @codArea               varchar(20),
    @txtMotivo             varchar(300),
    @txtUsuario            varchar(100),
    @codDepartamento       varchar(10)   = NULL,
    @codNivel              varchar(20)   = NULL,
    @txtPuesto             varchar(200)  = NULL,
    @numRemuneracionBasica decimal(18,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @codDepartamento = NULLIF(UPPER(TRIM(@codDepartamento)), '');
    SET @codNivel = NULLIF(UPPER(TRIM(@codNivel)), '');
    SET @txtPuesto = NULLIF(TRIM(@txtPuesto), '');

    IF @ideAsignacionArea IS NOT NULL
    BEGIN
        SELECT @numAnio = numAnio, @numMes = numMes, @idePersona = idePersona
        FROM proceso.TMD_ASIGNACION_AREA
        WHERE ideAsignacionArea = @ideAsignacionArea AND flgEstado = 1;

        IF @@ROWCOUNT = 0
            THROW 50125, 'La asignacion indicada no existe.', 1;
    END

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50120, 'El periodo esta cerrado: sus asignaciones de personal no se pueden modificar.', 1;

    IF NULLIF(TRIM(@txtMotivo), '') IS NULL
        THROW 50123, 'Indique el motivo de la asignacion.', 1;

    IF @codDepartamento NOT IN ('DGO', 'DIP', 'DPCM', 'RRCC', 'GO')
        THROW 50155, 'El departamento indicado no es valido: DGO, DIP, DPCM, RRCC o GO.', 1;

    IF @codNivel NOT IN ('JEFE', 'ADMINISTRATIVO', 'SUBORDINADO')
        THROW 50156, 'El nivel indicado no es valido: JEFE, ADMINISTRATIVO o SUBORDINADO.', 1;

    IF @numRemuneracionBasica < 0
        THROW 50157, 'La remuneracion basica no puede ser negativa.', 1;

    IF DB_ID('BD_SPRING') IS NULL
        THROW 50121, 'La persona no existe en SPRING (BD_SPRING no esta disponible).', 1;

    DECLARE @nomPersona varchar(150), @txtDocumento varchar(20), @nomArea varchar(200);

    EXEC sp_executesql N'
        SELECT @nombre = LEFT(TRIM(pm.NombreCompleto), 150), @documento = LEFT(TRIM(pm.Documento), 20)
        FROM BD_SPRING.dbo.PersonaMast pm
        WHERE pm.Persona = @persona;',
        N'@persona bigint, @nombre varchar(150) OUTPUT, @documento varchar(20) OUTPUT',
        @persona = @idePersona, @nombre = @nomPersona OUTPUT, @documento = @txtDocumento OUTPUT;

    IF @nomPersona IS NULL
        THROW 50121, 'La persona indicada no existe en SPRING.', 1;

    CREATE TABLE #areas (codArea varchar(20) NOT NULL, nomArea varchar(200) NOT NULL);
    INSERT INTO #areas (codArea, nomArea) EXEC proceso.usp_AreaSpring_Listar;

    SELECT @nomArea = nomArea FROM #areas WHERE codArea = TRIM(@codArea);
    IF @nomArea IS NULL
        THROW 50122, 'El area indicada no existe en SPRING.', 1;

    -- Igual que proceso.ufn_ClasificarCargo: solo esa gerencia entra al HH por proyecto.
    IF (@codDepartamento IS NOT NULL OR @codNivel IS NOT NULL)
       AND @nomArea COLLATE Latin1_General_CI_AI <> 'GERENCIA DE OPERACIONES'
        THROW 50158, 'El departamento y el nivel solo se asignan con el area GERENCIA DE OPERACIONES.', 1;

    IF EXISTS (SELECT 1 FROM proceso.TMD_ASIGNACION_AREA
               WHERE numAnio = @numAnio AND numMes = @numMes AND idePersona = @idePersona AND flgEstado = 1
                 AND ideAsignacionArea <> ISNULL(@ideAsignacionArea, 0))
        THROW 50124, 'La persona ya tiene una asignacion de area en el periodo.', 1;

    IF @ideAsignacionArea IS NULL
    BEGIN
        INSERT INTO proceso.TMD_ASIGNACION_AREA
               (numAnio, numMes, idePersona, nomPersona, txtDocumento, codArea, nomArea, txtMotivo,
                codDepartamento, codNivel, txtPuesto, numRemuneracionBasica,
                flgEstado, txtUsuarioCreacion)
        VALUES (@numAnio, @numMes, @idePersona, @nomPersona, @txtDocumento, TRIM(@codArea), @nomArea,
                TRIM(@txtMotivo), @codDepartamento, @codNivel, @txtPuesto, @numRemuneracionBasica,
                1, @txtUsuario);
        SET @ideAsignacionArea = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE proceso.TMD_ASIGNACION_AREA
        SET codArea = TRIM(@codArea),
            nomArea = @nomArea,
            txtMotivo = TRIM(@txtMotivo),
            codDepartamento = @codDepartamento,
            codNivel = @codNivel,
            txtPuesto = @txtPuesto,
            numRemuneracionBasica = @numRemuneracionBasica,
            fecActualizacion = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE ideAsignacionArea = @ideAsignacionArea;

    SELECT @ideAsignacionArea AS ideAsignacionArea;
END
GO

/* -------------------------------------------------------------------------
   4. Replicar del periodo anterior, con los datos del script 71
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_AsignacionArea_Replicar
    @numAnio    int,
    @numMes     int,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50120, 'El periodo esta cerrado: sus asignaciones de personal no se pueden modificar.', 1;

    DECLARE @numAnioOrigen int, @numMesOrigen int;

    SELECT TOP (1) @numAnioOrigen = numAnio, @numMesOrigen = numMes
    FROM proceso.TMD_ASIGNACION_AREA
    WHERE flgEstado = 1 AND numAnio * 100 + numMes < @numAnio * 100 + @numMes
    ORDER BY numAnio DESC, numMes DESC;

    IF @numAnioOrigen IS NULL
        THROW 50126, 'No hay un periodo anterior con asignaciones que replicar.', 1;

    INSERT INTO proceso.TMD_ASIGNACION_AREA
           (numAnio, numMes, idePersona, nomPersona, txtDocumento, codArea, nomArea, txtMotivo,
            codDepartamento, codNivel, txtPuesto, numRemuneracionBasica,
            flgEstado, txtUsuarioCreacion)
    SELECT @numAnio, @numMes, o.idePersona, o.nomPersona, o.txtDocumento, o.codArea, o.nomArea, o.txtMotivo,
           o.codDepartamento, o.codNivel, o.txtPuesto, o.numRemuneracionBasica,
           1, @txtUsuario
    FROM proceso.TMD_ASIGNACION_AREA o
    WHERE o.numAnio = @numAnioOrigen AND o.numMes = @numMesOrigen AND o.flgEstado = 1
      AND NOT EXISTS (SELECT 1 FROM proceso.TMD_ASIGNACION_AREA d
                      WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                        AND d.idePersona = o.idePersona AND d.flgEstado = 1);
    DECLARE @numCopiadas int = @@ROWCOUNT;

    SELECT @numAnioOrigen AS numAnioOrigen, @numMesOrigen AS numMesOrigen, @numCopiadas AS numCopiadas;
END
GO

/* -------------------------------------------------------------------------
   5. Reporte del costo labor
   ------------------------------------------------------------------------- */

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
        ('BD_REP19_TOTAL',               N'voucherno, voucherline'),
        ('BD_REP19_FILTRADO',            N'voucherno, voucherline'),
        -- Los tipos de gasto agrupados por proyecto van al final.
        ('RESUMEN_GRAL_GASTO_PERSONAL',  N'CASE WHEN txtTipoGasto IN (SELECT nomTipoGasto FROM TIPOS_GASTO_PROYECTO) THEN 1 ELSE 0 END, txtTipoGasto, account'),
        ('GASTOS_PERSONAL',              N'txtNombreCompleto, vendor'),
        ('DETALLE_GASTO_PERSONAL',       N'txtNombreCompleto'),
        ('RESUMEN_GASTO_PERSONAL',       N'GERENCIA'),
        ('RESUMEN_COSTO_LABOR',          N'CORE'),
        ('BD_DISTRIBUCION_COMPENSACION', N'txtCategoria, Proyecto, voucherno'),
        ('DISTRIBUCION_COMPENSACION',    N'FUENTE, PROYECTO'),
        ('HH_POR_PROYECTO',              N'CASE DEPARTAMENTO WHEN ''DGO'' THEN 1 WHEN ''DIP'' THEN 2 WHEN ''DPCM'' THEN 3 WHEN ''RRCC'' THEN 4 WHEN ''GO'' THEN 5 ELSE 6 END, '
                                         + N'CASE NIVEL WHEN ''GERENTE'' THEN 0 WHEN ''JEFE'' THEN 1 WHEN ''ADMINISTRATIVO'' THEN 2 ELSE 3 END, COLABORADOR'),
        ('COEFICIENTES',                 N'CASE DEPARTAMENTO WHEN ''DGO'' THEN 1 WHEN ''DIP'' THEN 2 WHEN ''DPCM'' THEN 3 WHEN ''RRCC'' THEN 4 WHEN ''GO'' THEN 5 ELSE 6 END, '
                                         + N'CASE NIVEL WHEN ''GERENTE'' THEN 0 WHEN ''JEFE'' THEN 1 WHEN ''ADMINISTRATIVO'' THEN 2 ELSE 3 END, COLABORADOR'),
        ('RELACION_GO',                  N'CASE DPTO WHEN ''DGO'' THEN 1 WHEN ''DIP'' THEN 2 WHEN ''DPCM'' THEN 3 WHEN ''RRCC'' THEN 4 WHEN ''GO'' THEN 5 ELSE 6 END, '
                                         + N'DPTO, PERSONAL'),
        ('TOTAL_COSTO_LABOR',           N'CASE FUENTE WHEN ''FA'' THEN 1 WHEN ''PAR'' THEN 2 WHEN ''28E'' THEN 3 WHEN ''TUCARI'' THEN 4 '
                                         + N'WHEN ''TUQUIAR'' THEN 5 WHEN ''PROINVERSION'' THEN 7 WHEN ''SIN DISTRIBUIR'' THEN 8 ELSE 6 END, PROYECTOS'),
        ('INCONSISTENCIAS',              N'TIPO, COLABORADOR, PROYECTO'),
        -- HU-009, HU-010 y HU-012 (script 41).
        ('GASTO_OPERATIVO_DEPARTAMENTO', N'CASE FUENTE WHEN ''FA'' THEN 1 WHEN ''PAR'' THEN 2 WHEN ''28E'' THEN 3 WHEN ''TUCARI'' THEN 4 '
                                         + N'WHEN ''TUQUIAR'' THEN 5 WHEN ''PROINVERSION'' THEN 7 WHEN ''SIN DISTRIBUIR'' THEN 8 ELSE 6 END, FUENTE, CODIGO'),
        ('INCIDENCIA_GASTO_OPERATIVO',   N'ORDEN'),
        ('RESOLUCION_COSTO_LABOR',       N'CASE FUENTE WHEN ''FA'' THEN 1 WHEN ''PAR'' THEN 2 WHEN ''28E'' THEN 3 WHEN ''TUCARI'' THEN 4 '
                                         + N'WHEN ''TUQUIAR'' THEN 5 WHEN ''PROINVERSION'' THEN 7 WHEN ''SIN DISTRIBUIR'' THEN 8 ELSE 6 END, PROYECTO');

    DECLARE @cte sysname, @orden nvarchar(400);
    SELECT @cte = codReporte, @orden = txtOrden
    FROM @reportes
    WHERE codReporte = UPPER(LTRIM(RTRIM(@codReporte)));

    IF @cte IS NULL
    BEGIN
        DECLARE @mensaje nvarchar(200) = CONCAT(N'El reporte ', ISNULL(@codReporte, N'(vacio)'), N' no existe.');
        THROW 50040, @mensaje, 1;
    END

    IF @cte = 'RELACION_GO' AND DB_ID('BD_SPRING') IS NULL
        THROW 50147, 'La base de datos BD_SPRING no esta disponible: la hoja RELACION_GO lee el documento y el sueldo de SPRING.', 1;

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

    -- Script 62: con el indicador activo el calculo toma todas las horas
    -- registradas, no solo las que la jefatura dejo CONFORME. Sin
    -- parametrizacion del periodo, o con el indicador nulo, exige validacion.
    -- Script 63: por debajo de este total del mes el trabajador entra al listado.
    DECLARE @horasMinimas decimal(14,4) = ISNULL((SELECT CAST(numParametro AS decimal(14,4))
                                                  FROM general.TG_CONFIGURACION
                                                  WHERE txtCodigoConfiguracion = 'HORAS_MINIMAS_INCONSISTENCIA'
                                                    AND flgEstado = 1), 160);

    DECLARE @flgSinValidacion bit = ISNULL((SELECT TOP (1) CAST(CASE WHEN flgHorasSinValidacion = 1 THEN 1 ELSE 0 END AS bit)
                                            FROM registro.TMC_PARAMETRO
                                            WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1), 0);

    -- Un porcentaje ausente daria montos en cero que parecen correctos.
    IF @porcDistGip IS NULL OR @porcDistGo IS NULL OR @porcGerenteCore1 IS NULL
       OR @porcGerenteCore2 IS NULL OR @porcCompensacion IS NULL
       OR @porcEscDgo IS NULL OR @porcEscDip IS NULL OR @porcEscDpcm IS NULL OR @porcEscRrcc IS NULL
       OR @porcGoDgo IS NULL OR @porcGoDip IS NULL OR @porcGoDpcm IS NULL OR @porcGoRrcc IS NULL
        THROW 50041, 'Faltan porcentajes del costo labor en general.TG_CONFIGURACION (DIST_*, PORC_GG_*, PORC_GO_* o PORC_COMPENSACION).', 1;

    IF ISNULL(@horasReferencia, 0) <= 0
        THROW 50042, 'Falta HORAS_MES_REFERENCIA en general.TG_CONFIGURACION: debe ser mayor a cero.', 1;

    /* --------------------------- Compensacion del periodo (script 68) */
    -- Se lee una sola vez de la vista y se guarda en una tabla temporal, que
    -- la cadena de CTE usa en lugar de la vista. Con el filtro de vouchers
    -- excluidos (script 67) dentro de la consulta unica, SQL Server no llega a
    -- armar el plan (error 8623) o tarda minutos. El sp_executesql de abajo
    -- ve esta tabla porque se ejecuta dentro de este mismo procedimiento.
    SELECT c.period, c.DescripcionLocal, c.Proyecto, ISNULL(c.Monto, 0) AS Monto, c.englishname,
           c.txtCategoria, c.Account, c.voucherno, c.vendor, c.invoice
    INTO #BD_DISTRIBUCION_COMPENSACION
    FROM proceso.VW_DISTRIBUCION_COMPENSACION_REPORTE c
    WHERE c.idePeriodo = @idePeriodo;

    /* --------------------------------------------- Cadena de CTE comun */
    DECLARE @sql nvarchar(max) = N'
WITH GASTO_PERIODO AS (
    SELECT g.voucherno, g.txtTipoGasto, g.voucherline, g.vendor, g.status, g.txtLocalName,
           ISNULL(g.localamount, 0) AS localamount, g.idePersona, g.txtNombreCompleto, g.account,
           g.Documento, g.Area, g.Departamento, g.Cargo, g.CostCenter, g.CentroCostos, g.period,
           -- La fecha de cese de SPRING no trae hora.
           g.afe AS codProyecto, CAST(g.fecCese AS date) AS FechaCese, g.flgProyectoExcluido,
           g.flgApExcluido, g.AreaSpring,
           -- Proveedor: quien no es empleado (sin registro en EmpleadoMast o sin
           -- puesto en HR_PuestoEmpresa), no quien tiene el area vacia.
           CASE WHEN NULLIF(TRIM(g.Cargo), '''') IS NULL THEN 1 ELSE 0 END AS flgProveedor
    -- Correcciones 27/09: los filtros que antes aplicaba la extraccion.
    FROM proceso.VW_GASTO_PERSONAL_REPORTE g
    WHERE g.idePeriodo = @idePeriodo
),

-- Todas las lineas del periodo, tambien las de proyectos y vouchers
-- excluidos: es la hoja BD_REP19_TOTAL. Script 70: con el area de SPRING,
-- sin asignacion del Contador ni relleno.
BD_REP19_TOTAL AS (
    SELECT voucherno, txtTipoGasto, voucherline, vendor, status, txtLocalName, localamount,
           idePersona, txtNombreCompleto, account, Documento, AreaSpring AS Area, Departamento, Cargo,
           CostCenter, CentroCostos, period, codProyecto, FechaCese
    FROM GASTO_PERIODO
),

-- Lo que entra al costo labor: sin las lineas de proyectos excluidos del
-- periodo (proceso.TMD_PROYECTO_EXCLUIDO). Los cuadros que siguen leen esta.
GASTO_CALCULO AS (
    SELECT *
    FROM GASTO_PERIODO
    WHERE flgProyectoExcluido = 0 AND flgApExcluido = 0
),

-- Las mismas columnas que BD_REP19_TOTAL, pero solo lo que entra al costo
-- labor: asi el usuario ve que vouchers alimentan las hojas que siguen.
BD_REP19_FILTRADO AS (
    SELECT voucherno, txtTipoGasto, voucherline, vendor, status, txtLocalName, localamount,
           idePersona, txtNombreCompleto, account, Documento, Area, Departamento, Cargo,
           CostCenter, CentroCostos, period, codProyecto, FechaCese
    FROM GASTO_CALCULO
),

-- Tipos de gasto vigentes para el periodo, como en el procesamiento: los del
-- periodo o los del ultimo anterior que tenga; sin ninguno anterior, los mas antiguos.
TIPOS_GASTO_PROYECTO AS (
    SELECT t.nomTipoGasto
    FROM proceso.TMC_TIPO_GASTO t
    WHERE t.flgEstado = 1 AND t.codAgrupacion = ''PROYECTO''
      AND t.numAnio * 100 + t.numMes = COALESCE(
          (SELECT MAX(numAnio * 100 + numMes) FROM proceso.TMC_TIPO_GASTO
           WHERE flgEstado = 1 AND numAnio * 100 + numMes <= @numAnio * 100 + @numMes),
          (SELECT MIN(numAnio * 100 + numMes) FROM proceso.TMC_TIPO_GASTO WHERE flgEstado = 1))
),

-- Al final (ver el orden del reporte), los tipos agrupados por proyecto con lo
-- de los proyectos excluidos: no entra al costo labor, pero se muestra.
RESUMEN_GRAL_GASTO_PERSONAL AS (
    SELECT txtTipoGasto, txtLocalName, account, SUM(localamount) AS TOTAL
    FROM (
        SELECT txtTipoGasto, txtLocalName, account, localamount
        FROM GASTO_CALCULO
        UNION ALL
        SELECT txtTipoGasto, txtLocalName, account, localamount
        FROM GASTO_PERIODO
        WHERE flgProyectoExcluido = 1
          AND txtTipoGasto IN (SELECT nomTipoGasto FROM TIPOS_GASTO_PROYECTO)
    ) l
    GROUP BY txtTipoGasto, txtLocalName, account
    -- Script 70: sin las cuentas que suman cero.
    HAVING ROUND(SUM(localamount), 2) <> 0
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

-- Proveedores: su gasto se reparte entre todos como OTROS. Si el contador los
-- puso en un grupo de gasto no recuperable, quedan fuera.
TOTAL_PROVEEDORES AS (
    SELECT CAST(ISNULL(SUM(localamount), 0) AS decimal(14,4)) AS TOTAL
    FROM GASTO_CALCULO
    WHERE txtTipoGasto = ''Gasto de Personal'' AND flgProveedor = 1
      AND vendor NOT IN (SELECT idePersona FROM GRUPOS_PERSONA)
),

TOTAL_SUELDOS_Y_SALARIOS AS (
    SELECT CAST(ISNULL(SUM(localamount), 0) AS decimal(14,4)) AS TOTAL
    FROM GASTO_CALCULO
    WHERE txtTipoGasto = ''Gasto de Personal'' AND account = ''62110010''
),

TOTAL_ASIGNACION_FAMILIAR AS (
    SELECT CAST(ISNULL(SUM(localamount), 0) AS decimal(14,4)) AS TOTAL
    FROM GASTO_CALCULO
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

-- Mano de obra por trabajador. OTROS reparte el gasto de los proveedores en
-- proporcion a (sueldos + asignacion familiar) de cada uno; el proveedor no
-- tiene fila propia: su gasto ya esta en OTROS.
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
    FROM GASTO_CALCULO r
    LEFT JOIN GERENCIAS ge ON ge.Area = r.Area
    WHERE r.txtTipoGasto = ''Gasto de Personal'' AND r.flgProveedor = 0
    GROUP BY r.vendor, r.txtNombreCompleto, r.Documento, r.Area, r.Departamento, COALESCE(ge.Gerencia, r.Area), r.Cargo
),

-- Hoja GASTOS_PERSONAL: el gasto de personal por persona y cuenta, antes de
-- repartir el de los proveedores en OTROS. Una columna por cuenta del periodo.
-- Script 70: sin las personas de total cero ni las cuentas en cero para
-- todas ellas (una cuenta de neto cero con montos que se compensan entre
-- personas se queda, para no cambiar el total de cada fila).
CUENTAS_GASTO_PERSONAL AS (
    SELECT account, LEFT(CONCAT(account, '' '', MAX(txtLocalName)), 128) AS CUENTA
    FROM (
        SELECT account, MAX(txtLocalName) AS txtLocalName, SUM(localamount) AS monto
        FROM GASTO_CALCULO
        WHERE txtTipoGasto = ''Gasto de Personal''
        GROUP BY account, vendor, txtNombreCompleto, Documento, Area, Departamento, Cargo
    ) p
    GROUP BY account
    HAVING MAX(ABS(ROUND(monto, 2))) > 0
),

GASTOS_PERSONAL_BASE AS (
    SELECT vendor, txtNombreCompleto, Documento, Area, Departamento, Cargo, CUENTA, localamount
    FROM (
        SELECT r.vendor, r.txtNombreCompleto, r.Documento, r.Area, r.Departamento, r.Cargo,
               c.CUENTA, r.localamount,
               -- Total de la fila del PIVOT.
               SUM(r.localamount) OVER (PARTITION BY r.vendor, r.txtNombreCompleto, r.Documento,
                                                     r.Area, r.Departamento, r.Cargo) AS totalPersona
        FROM GASTO_CALCULO r
        JOIN CUENTAS_GASTO_PERSONAL c ON c.account = r.account
        WHERE r.txtTipoGasto = ''Gasto de Personal''
    ) b
    WHERE ROUND(totalPersona, 2) <> 0
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

-- El Gerente General titular o el encargado: "GERENTE GENERAL" solo o seguido
-- de un parentesis, como "GERENTE GENERAL (E)". No entra un cargo que solo
-- empieza igual, como "GERENTE GENERAL - GERENTE LEGAL (E)".
TOTAL_GERENTE_GENERAL AS (
    SELECT CAST(ISNULL(SUM(SUELDOS_Y_SALARIOS + GRATIFICACIONES + VACACIONES + ASIGNACION_FAMILIAR
               + REGIMEN_DE_PRESTACIONES_DE_SALUD + SEGUROS_PARTICULARES_DE_SALUD_EPS_Y_OTROS_PARTIC
               + COMPENSACION_POR_TIEMPO_DE_SERVICIO + OTROS), 0) AS decimal(14,4)) AS TOTAL
    FROM DETALLE_GASTO_PERSONAL
    WHERE (TRIM(Cargo) = ''GERENTE GENERAL''
           OR TRIM(Cargo) LIKE ''GERENTE GENERAL (%''
           OR TRIM(Cargo) LIKE ''GERENTE GENERAL(%'')
      AND Gerencia = ''GG''
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
    FROM GASTO_CALCULO
    WHERE txtTipoGasto = ''Gasto Operativo''
),

BD_DISTRIBUCION_COMPENSACION AS (
    SELECT c.period, c.DescripcionLocal, c.Proyecto, c.Monto, c.englishname,
           c.txtCategoria, c.Account, c.voucherno, c.vendor, c.invoice
    FROM #BD_DISTRIBUCION_COMPENSACION c
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
           MAX(Area) AS Area, MAX(Departamento) AS Departamento, MAX(Cargo) AS Cargo,
           MAX(Documento) AS Documento
    FROM GASTO_CALCULO
    WHERE txtTipoGasto = ''Gasto de Personal'' AND vendor IS NOT NULL
    GROUP BY vendor
),

-- Script 71: lo que el Contador registro para la persona en el periodo.
ASIGNACION_PERIODO AS (
    SELECT idePersona, codDepartamento, codNivel, txtPuesto, numRemuneracionBasica
    FROM proceso.TMD_ASIGNACION_AREA
    WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1
),

-- Script 71: el departamento y el nivel de la asignacion mandan; si no los
-- trae, se clasifica con el puesto asignado o, sin el, con el cargo de SPRING.
-- El area ya viene con la de la asignacion (VW_GASTO_PERSONAL_REPORTE).
EMPLEADOS AS (
    SELECT p.ideEmpleado, p.nomEmpleado, b.Cargo,
           COALESCE(a.codDepartamento, c.codDepartamento) AS codDepartamento,
           COALESCE(a.codNivel, c.codNivel) AS codNivel,
           a.codDepartamento AS codDepartamentoAsignado,
           p.Area, p.Departamento, p.Documento, a.numRemuneracionBasica
    FROM PERSONAL_PERIODO p
    LEFT JOIN ASIGNACION_PERIODO a ON a.idePersona = p.ideEmpleado
    CROSS APPLY (SELECT COALESCE(a.txtPuesto, p.Cargo) AS Cargo) b
    CROSS APPLY proceso.ufn_ClasificarCargo(p.Area, p.Departamento, b.Cargo) c
    WHERE @idePeriodo IS NOT NULL
),

-- Fuente de cada proyecto: la Categorizacion de proyectos (script 37) vigente
-- para el periodo, la misma que usa el procesamiento: la del periodo o la del
-- ultimo anterior que tenga; sin ninguna anterior, la mas antigua. Antes salia
-- de proceso.TMC_PROYECTO_FUENTE, que ya no se usa (decision del 13/10).
CATEGORIZACION_VIGENTE AS (
    SELECT COALESCE(
        (SELECT TOP (1) numAnio * 100 + numMes FROM proceso.TMC_CATEGORIA_PROYECTO
         WHERE flgEstado = 1 AND numAnio * 100 + numMes <= @numAnio * 100 + @numMes
         ORDER BY numAnio DESC, numMes DESC),
        (SELECT TOP (1) numAnio * 100 + numMes FROM proceso.TMC_CATEGORIA_PROYECTO
         WHERE flgEstado = 1
         ORDER BY numAnio, numMes)) AS PERIODO
),

PROYECTO_FUENTE AS (
    SELECT d.codProyecto AS codClave, d.codProyecto, c.codCategoria AS codFuente, d.nomProyecto
    FROM proceso.TMD_CATEGORIA_PROYECTO_DETALLE d
    JOIN proceso.TMC_CATEGORIA_PROYECTO c
      ON c.ideCategoriaProyecto = d.ideCategoriaProyecto AND c.flgEstado = 1
    CROSS JOIN CATEGORIZACION_VIGENTE v
    WHERE d.flgEstado = 1 AND d.numAnio * 100 + d.numMes = v.PERIODO
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
     AND (@flgSinValidacion = 1 OR v.codEstadoValidacion = ''CONFORME'')
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
        CAST(SUM(SUELDOS_Y_SALARIOS + GRATIFICACIONES + VACACIONES + ASIGNACION_FAMILIAR
            + REGIMEN_DE_PRESTACIONES_DE_SALUD + SEGUROS_PARTICULARES_DE_SALUD_EPS_Y_OTROS_PARTIC
            + COMPENSACION_POR_TIEMPO_DE_SERVICIO + OTROS) AS float) AS COSTO
    FROM DETALLE_GASTO_PERSONAL
    -- El gasto no recuperable no se reparte por proyecto.
    WHERE vendor NOT IN (SELECT idePersona FROM GRUPOS_PERSONA)
    GROUP BY vendor
),

-- Excel "HH por proyecto 2", columnas CD a CF y una por proyecto: el
-- subordinado con horas validadas reparte sus horas ajustadas (las
-- ejecutadas, o las de referencia si trabajo menos) con su coeficiente de la
-- hoja 1 (horas del proyecto / horas ejecutadas).
HORAS_AJUSTADAS AS (
    SELECT e.ideEmpleado, e.codDepartamento, h.codClave,
        CASE WHEN he.HORAS_EJECUTADAS >= @horasReferencia THEN he.HORAS_EJECUTADAS
             ELSE CAST(@horasReferencia AS float) END * h.HORAS / he.HORAS_EJECUTADAS AS HORAS
    FROM EMPLEADOS e
    JOIN HORAS_EMPLEADO he ON he.ideEmpleado = e.ideEmpleado
    JOIN HORAS_VALIDADAS h ON h.ideEmpleado = e.ideEmpleado
    WHERE e.codNivel = ''SUBORDINADO''
),

-- Excel: fila JEFE de cada departamento, la suma de las horas de sus
-- subordinados entre cuantos son ("Nro.Subordinados"). Cuentan los que
-- tienen horas validadas: los demas no aportan horas al promedio.
HORAS_JEFE AS (
    SELECT a.codDepartamento, a.codClave, SUM(a.HORAS) / MAX(n.SUBORDINADOS) AS HORAS
    FROM HORAS_AJUSTADAS a
    JOIN (SELECT codDepartamento, COUNT(DISTINCT ideEmpleado) AS SUBORDINADOS
          FROM HORAS_AJUSTADAS
          GROUP BY codDepartamento) n ON n.codDepartamento = a.codDepartamento
    WHERE a.codDepartamento IN (''DGO'', ''DIP'', ''DPCM'', ''RRCC'')
    GROUP BY a.codDepartamento, a.codClave
),

-- El coeficiente del jefe es el del departamento: reparte tambien al
-- Gerente General, las areas de apoyo y el gasto operativo de cada uno.
PROPORCION_DEPARTAMENTO AS (
    SELECT codDepartamento, codClave,
        HORAS / NULLIF(SUM(HORAS) OVER (PARTITION BY codDepartamento), 0) AS PROPORCION
    FROM HORAS_JEFE
),

-- Excel: fila GO, el promedio de los jefes de los departamentos con horas.
HORAS_GERENCIA AS (
    SELECT codClave, SUM(HORAS) / (SELECT COUNT(DISTINCT codDepartamento) FROM HORAS_JEFE) AS HORAS
    FROM HORAS_JEFE
    GROUP BY codClave
),

-- Horas de cada colaborador por proyecto, las de la pestania 4. El Excel
-- copia la fila GO en la del administrativo de cada departamento y en la del
-- personal de la gerencia; el subordinado de la gerencia sin horas
-- validadas, que el sistema no distingue del administrativo, tambien la toma.
HORAS_COLABORADOR AS (
    SELECT ideEmpleado, codClave, HORAS
    FROM HORAS_AJUSTADAS
    UNION ALL
    SELECT e.ideEmpleado, j.codClave, j.HORAS
    FROM EMPLEADOS e
    JOIN HORAS_JEFE j ON j.codDepartamento = e.codDepartamento
    WHERE e.codNivel = ''JEFE''
    UNION ALL
    SELECT e.ideEmpleado, g.codClave, g.HORAS
    FROM EMPLEADOS e
    CROSS JOIN HORAS_GERENCIA g
    WHERE e.codNivel IN (''GERENTE'', ''ADMINISTRATIVO'')
       OR (e.codDepartamento = ''GO'' AND e.codNivel = ''JEFE'')
       OR (e.codDepartamento = ''GO'' AND e.codNivel = ''SUBORDINADO''
           AND NOT EXISTS (SELECT 1 FROM HORAS_EMPLEADO he WHERE he.ideEmpleado = e.ideEmpleado))
),

-- Coeficiente de cada colaborador: sus horas del proyecto / su total. El
-- subordinado de un departamento sin horas validadas no tiene fila en la
-- pestania 4, pero su gasto se reparte con el coeficiente de su departamento.
PROPORCION_EMPLEADO AS (
    SELECT ideEmpleado, codClave, HORAS / NULLIF(SUM(HORAS) OVER (PARTITION BY ideEmpleado), 0) AS PROPORCION
    FROM HORAS_COLABORADOR
    UNION ALL
    SELECT e.ideEmpleado, pd.codClave, pd.PROPORCION
    FROM EMPLEADOS e
    JOIN PROPORCION_DEPARTAMENTO pd ON pd.codDepartamento = e.codDepartamento
    WHERE e.codNivel = ''SUBORDINADO''
      AND NOT EXISTS (SELECT 1 FROM HORAS_EMPLEADO he WHERE he.ideEmpleado = e.ideEmpleado)
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

/* ------------------------------------------------------------------------
   HU-009: gasto operativo por proyecto y departamento. Cada departamento de
   la Gerencia de Operaciones reparte su porcentaje del gasto operativo con
   la misma proporcion de horas del costo labor; la parte de la GIP (Linea
   Core 1) va a PROINVERSION. Se listan todos los proyectos de la
   distribucion de compensacion, aunque no tengan gasto.
   ------------------------------------------------------------------------ */
GO_DEPARTAMENTO_PROYECTO AS (
    SELECT pd.codClave, pd.codDepartamento,
           pd.PROPORCION * CAST(g.TOTAL AS float) * CAST(pc.PORC_OPERATIVO AS float) / 100 AS MONTO
    FROM PROPORCION_DEPARTAMENTO pd
    JOIN PORCENTAJES_DEPARTAMENTO pc ON pc.codDepartamento = pd.codDepartamento
    CROSS JOIN TOTAL_GASTO_OPERATIVO g
),

GO_PIVOTE AS (
    SELECT codClave,
           SUM(CASE WHEN codDepartamento = ''DGO''  THEN MONTO ELSE 0 END) AS DGO,
           SUM(CASE WHEN codDepartamento = ''DIP''  THEN MONTO ELSE 0 END) AS DIP,
           SUM(CASE WHEN codDepartamento = ''DPCM'' THEN MONTO ELSE 0 END) AS DPCM,
           SUM(CASE WHEN codDepartamento = ''RRCC'' THEN MONTO ELSE 0 END) AS RRCC
    FROM GO_DEPARTAMENTO_PROYECTO
    GROUP BY codClave
),

GO_PROYECTOS AS (
    SELECT codClave FROM PROYECTOS_COMPENSACION
    UNION
    SELECT codClave FROM GO_PIVOTE
),

GASTO_OPERATIVO_DEPARTAMENTO AS (
    SELECT COALESCE(pf.codFuente, cp.FUENTE, ''SIN FUENTE'') AS FUENTE,
           p.codClave AS CODIGO,
           CONCAT(CASE WHEN COUNT(*) OVER (PARTITION BY RIGHT(p.codClave, 6)) > 1
                       THEN p.codClave ELSE RIGHT(p.codClave, 6) END,
                  ''-'', COALESCE(pf.nomProyecto, cp.nomProyecto, nh.nomProyecto)) AS PROYECTOS,
           CAST(ISNULL(v.DGO, 0)  AS decimal(14,4)) AS DGO,
           CAST(ISNULL(v.DIP, 0)  AS decimal(14,4)) AS DIP,
           CAST(ISNULL(v.DPCM, 0) AS decimal(14,4)) AS DPCM,
           CAST(ISNULL(v.RRCC, 0) AS decimal(14,4)) AS RRCC,
           CAST(0 AS decimal(14,4)) AS GIP
    FROM GO_PROYECTOS p
    LEFT JOIN GO_PIVOTE v ON v.codClave = p.codClave
    LEFT JOIN PROYECTO_FUENTE pf ON pf.codClave = p.codClave
    LEFT JOIN PROYECTOS_COMPENSACION cp ON cp.codClave = p.codClave
    LEFT JOIN NOMBRES_HORAS nh ON nh.codClave = p.codClave
    WHERE @idePeriodo IS NOT NULL
    UNION ALL
    SELECT ''PROINVERSION'', NULL, ''PROINVERSION'', 0, 0, 0, 0,
           CAST(g.TOTAL * @porcDistGip / 100 AS decimal(14,4))
    FROM TOTAL_GASTO_OPERATIVO g
    WHERE @idePeriodo IS NOT NULL
    UNION ALL
    -- Lo que cada departamento no pudo repartir por falta de horas validadas.
    -- Cualquier residuo, aun de centimos, para que la matriz cuadre con la incidencia.
    SELECT ''SIN DISTRIBUIR'', NULL, ''SIN DISTRIBUIR (FALTAN HORAS VALIDADAS)'',
           CAST(g.TOTAL * @porcGoDgo  / 100 - ISNULL(t.DGO, 0)  AS decimal(14,4)),
           CAST(g.TOTAL * @porcGoDip  / 100 - ISNULL(t.DIP, 0)  AS decimal(14,4)),
           CAST(g.TOTAL * @porcGoDpcm / 100 - ISNULL(t.DPCM, 0) AS decimal(14,4)),
           CAST(g.TOTAL * @porcGoRrcc / 100 - ISNULL(t.RRCC, 0) AS decimal(14,4)),
           CAST(0 AS decimal(14,4))
    FROM TOTAL_GASTO_OPERATIVO g
    CROSS JOIN (SELECT SUM(DGO) AS DGO, SUM(DIP) AS DIP, SUM(DPCM) AS DPCM, SUM(RRCC) AS RRCC FROM GO_PIVOTE) t
    WHERE @idePeriodo IS NOT NULL
      AND (ABS(g.TOTAL * @porcGoDgo / 100 - ISNULL(t.DGO, 0)) >= 0.00005
           OR ABS(g.TOTAL * @porcGoDip / 100 - ISNULL(t.DIP, 0)) >= 0.00005
           OR ABS(g.TOTAL * @porcGoDpcm / 100 - ISNULL(t.DPCM, 0)) >= 0.00005
           OR ABS(g.TOTAL * @porcGoRrcc / 100 - ISNULL(t.RRCC, 0)) >= 0.00005)
),

/* HU-009 CA-02: el gasto operativo del periodo y los porcentajes de incidencia. */
INCIDENCIA_GASTO_OPERATIVO AS (
    SELECT d.ORDEN, d.DEPARTAMENTO, CAST(d.PORCENTAJE / 100 AS decimal(14,6)) AS PORCENTAJE,
           CAST(g.TOTAL * d.PORCENTAJE / 100 AS decimal(14,4)) AS MONTO
    FROM (VALUES (1, ''GIP'',  @porcDistGip),
                 (2, ''DGO'',  @porcGoDgo),
                 (3, ''DIP'',  @porcGoDip),
                 (4, ''DPCM'', @porcGoDpcm),
                 (5, ''RRCC'', @porcGoRrcc)) AS d(ORDEN, DEPARTAMENTO, PORCENTAJE)
    CROSS JOIN TOTAL_GASTO_OPERATIVO g
    WHERE @idePeriodo IS NOT NULL
    UNION ALL
    SELECT 0, ''GASTO OPERATIVO'', NULL, TOTAL
    FROM TOTAL_GASTO_OPERATIVO
    WHERE @idePeriodo IS NOT NULL
),

/* HU-012: costo labor del mes por proyecto con la referencia de gastos de
   capital (la base de la compensacion). El rango de meses lo suma el backend. */
BASE_COMPENSACION AS (
    SELECT Proyecto AS codClave, SUM(Monto) AS MONTO
    FROM BD_DISTRIBUCION_COMPENSACION
    GROUP BY Proyecto
),

RESOLUCION_COSTO_LABOR AS (
    SELECT t.FUENTE, t.CODIGO,
           -- Solo el nombre: el proyecto de resolucion no muestra el codigo.
           STUFF(t.PROYECTOS, 1, CASE WHEN t.CODIGO IS NULL THEN 0 ELSE CHARINDEX(''-'', t.PROYECTOS) END, '''') AS PROYECTO,
           CAST(ISNULL(b.MONTO, 0) AS decimal(14,4)) AS REFERENCIA_GASTOS_CAPITAL,
           t.MANO_DE_OBRA, t.GASTO_OPERATIVO, t.COMPENSACION
    FROM TOTAL_COSTO_LABOR t
    LEFT JOIN BASE_COMPENSACION b ON b.codClave = t.CODIGO
),

-- Pestania 4: horas por colaborador como "HH por proyecto 2" (ajustadas o
-- calculadas); el SELECT final las pivota por proyecto.
HH_BASE AS (
    SELECT e.codDepartamento AS DEPARTAMENTO, e.codNivel AS NIVEL, e.ideEmpleado AS CODIGO,
           e.nomEmpleado AS COLABORADOR, e.Cargo AS PUESTO,
           ph.PROYECTO, ph.ORDEN_FUENTE,
           CAST(h.HORAS AS decimal(18,2)) AS HORAS
    FROM EMPLEADOS e
    LEFT JOIN HORAS_COLABORADOR h ON h.ideEmpleado = e.ideEmpleado
    LEFT JOIN PROYECTOS_HH ph ON ph.codClave = h.codClave
),

-- Script 64. El coeficiente de la hoja "HH por proyecto 1" del contador:
-- que parte de las horas del colaborador se fue a cada proyecto. Cada fila
-- suma 1. Se expone para que el usuario vea de donde sale el reparto.
COEF_BASE AS (
    SELECT DEPARTAMENTO, NIVEL, CODIGO, COLABORADOR, PUESTO, PROYECTO, ORDEN_FUENTE,
           CAST(HORAS / NULLIF(SUM(HORAS) OVER (PARTITION BY CODIGO), 0) AS decimal(18,4)) AS COEFICIENTE
    FROM HH_BASE
),

-- Correcciones 27/09: horas registradas en proyectos que no estan en la
-- distribucion de compensacion de SPRING. Se listan todas, validadas o no,
-- para corregirlas antes de aprobar el periodo.
-- Dos tipos (script 63). El segundo mira el total del mes por trabajador,
-- asi que no tiene proyecto; jefes, administrativos y gerentes quedan fuera
-- porque sus horas se calculan, no se registran.
INCONSISTENCIAS AS (
    SELECT CAST(''PROYECTO SIN COMPENSACION'' AS varchar(40)) AS TIPO,
           r.ideEmpleado AS CODIGO, MAX(r.nomEmpleado) AS COLABORADOR,
           CAST(r.codProyecto AS varchar(30)) AS PROYECTO, MAX(r.nomProyecto) AS NOMBRE_PROYECTO,
           ISNULL(MAX(v.codEstadoValidacion), ''PENDIENTE'') AS ESTADO,
           CAST(SUM(r.numHoras) AS decimal(18,2)) AS HORAS
    FROM registro.TMD_REGISTRO_HORAMES r
    LEFT JOIN registro.VW_REGISTRO_HORAMES_ESTADO v
           ON v.ideEmpleado = r.ideEmpleado AND v.numAnio = r.numAnio AND v.numMes = r.numMes
    WHERE r.numAnio = @numAnio AND r.numMes = @numMes AND r.flgEstado = 1 AND r.numHoras > 0
      AND @idePeriodo IS NOT NULL
      AND CASE WHEN LEN(r.codProyecto) = 6 THEN CONCAT(''000000'', r.codProyecto) ELSE r.codProyecto END NOT IN (SELECT codClave FROM PROYECTOS_COMPENSACION)
    GROUP BY r.ideEmpleado, r.codProyecto

    UNION ALL

    SELECT CAST(''HORAS INSUFICIENTES'' AS varchar(40)) AS TIPO,
           r.ideEmpleado AS CODIGO, MAX(r.nomEmpleado) AS COLABORADOR,
           CAST(NULL AS varchar(30)) AS PROYECTO, CAST(NULL AS varchar(200)) AS NOMBRE_PROYECTO,
           ISNULL(MAX(v.codEstadoValidacion), ''PENDIENTE'') AS ESTADO,
           CAST(SUM(r.numHoras) AS decimal(18,2)) AS HORAS
    FROM registro.TMD_REGISTRO_HORAMES r
    LEFT JOIN registro.VW_REGISTRO_HORAMES_ESTADO v
           ON v.ideEmpleado = r.ideEmpleado AND v.numAnio = r.numAnio AND v.numMes = r.numMes
    LEFT JOIN EMPLEADOS e ON e.ideEmpleado = r.ideEmpleado
    WHERE r.numAnio = @numAnio AND r.numMes = @numMes AND r.flgEstado = 1 AND r.numHoras > 0
      AND @idePeriodo IS NOT NULL
      AND ISNULL(e.codNivel, ''SUBORDINADO'') NOT IN (''JEFE'', ''ADMINISTRATIVO'', ''GERENTE'')
    GROUP BY r.ideEmpleado
    HAVING SUM(r.numHoras) <= @horasMinimas
)
';

    DECLARE @parametros nvarchar(max) = N'@idePeriodo bigint, @numAnio int, @numMes int,
          @porcDistGip decimal(14,4), @porcDistGo decimal(14,4),
          @porcGerenteCore1 decimal(14,4), @porcGerenteCore2 decimal(14,4), @porcCompensacion decimal(14,4),
          @porcEscDgo decimal(14,4), @porcEscDip decimal(14,4), @porcEscDpcm decimal(14,4), @porcEscRrcc decimal(14,4),
          @porcGoDgo decimal(14,4), @porcGoDip decimal(14,4), @porcGoDpcm decimal(14,4), @porcGoRrcc decimal(14,4),
          @horasReferencia decimal(14,4), @flgSinValidacion bit, @horasMinimas decimal(14,4)';

    /* Pestania 4: una columna por proyecto de la distribucion de compensacion
       (correcciones 27/09). La lista sale de la misma cadena de CTE, asi el
       nombre de cada columna coincide con el del PIVOT. */
    DECLARE @columnas nvarchar(max), @columnasSelect nvarchar(max);
    IF @cte IN ('HH_POR_PROYECTO', 'COEFICIENTES')
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
            @horasReferencia = @horasReferencia, @flgSinValidacion = @flgSinValidacion,
            @horasMinimas = @horasMinimas,
            @columnas = @columnas OUTPUT, @columnasSelect = @columnasSelect OUTPUT;
    END

    /* GASTOS_PERSONAL: una columna por cuenta del gasto de personal del
       periodo ("62110010 SUELDOS Y SALARIOS"), en orden de cuenta. Como en la
       pestania 4, la lista sale de la misma cadena de CTE. */
    DECLARE @cuentas nvarchar(max);
    IF @cte = 'GASTOS_PERSONAL'
    BEGIN
        DECLARE @sqlCuentas nvarchar(max) = @sql + N'
SELECT @cuentas = STRING_AGG(CAST(QUOTENAME(CUENTA) AS nvarchar(max)), N'','') WITHIN GROUP (ORDER BY account)
FROM CUENTAS_GASTO_PERSONAL;';

        DECLARE @parametrosCuentas nvarchar(max) = @parametros + N', @cuentas nvarchar(max) OUTPUT';

        EXEC sp_executesql @sqlCuentas, @parametrosCuentas,
            @idePeriodo = @idePeriodo, @numAnio = @numAnio, @numMes = @numMes,
            @porcDistGip = @porcDistGip, @porcDistGo = @porcDistGo,
            @porcGerenteCore1 = @porcGerenteCore1, @porcGerenteCore2 = @porcGerenteCore2,
            @porcCompensacion = @porcCompensacion,
            @porcEscDgo = @porcEscDgo, @porcEscDip = @porcEscDip, @porcEscDpcm = @porcEscDpcm, @porcEscRrcc = @porcEscRrcc,
            @porcGoDgo = @porcGoDgo, @porcGoDip = @porcGoDip, @porcGoDpcm = @porcGoDpcm, @porcGoRrcc = @porcGoRrcc,
            @horasReferencia = @horasReferencia, @flgSinValidacion = @flgSinValidacion,
            @horasMinimas = @horasMinimas,
            @cuentas = @cuentas OUTPUT;
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

COEFICIENTES AS (
    SELECT DEPARTAMENTO, NIVEL, CODIGO, COLABORADOR, PUESTO'
        + CASE WHEN @columnas IS NULL
               THEN N' FROM (SELECT DISTINCT DEPARTAMENTO, NIVEL, CODIGO, COLABORADOR, PUESTO FROM COEF_BASE) b'
               ELSE N', ' + @columnasSelect
                    + N' FROM (SELECT DEPARTAMENTO, NIVEL, CODIGO, COLABORADOR, PUESTO, PROYECTO, COEFICIENTE FROM COEF_BASE) b'
                    + N' PIVOT (SUM(COEFICIENTE) FOR PROYECTO IN (' + @columnas + N')) pv'
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
),

GASTOS_PERSONAL AS (
    SELECT vendor, txtNombreCompleto, Documento, Area, Departamento, Cargo'
        + CASE WHEN @cuentas IS NULL
               -- Sin gasto de personal en el periodo: sin columnas de cuenta.
               THEN N' FROM (SELECT DISTINCT vendor, txtNombreCompleto, Documento, Area, Departamento, Cargo FROM GASTOS_PERSONAL_BASE) b'
               -- La celda sin gasto queda vacia, como en la tabla dinamica del contador.
               ELSE N', ' + @cuentas
                    + N' FROM (SELECT vendor, txtNombreCompleto, Documento, Area, Departamento, Cargo, CUENTA, localamount FROM GASTOS_PERSONAL_BASE) b'
                    + N' PIVOT (SUM(localamount) FOR CUENTA IN (' + @cuentas + N')) pv'
          END
        + N'
)'
        -- Solo se arma si se pide: lee BD_SPRING, que no se necesita para el resto.
        + CASE WHEN @cte <> 'RELACION_GO' THEN N''
               ELSE N',

-- Hoja RelacionGO. Script 71: el mismo personal que HH_POR_PROYECTO, tenga o
-- no horas, con su departamento, nivel y puesto del calculo (los de la
-- asignacion, si la hay). De SPRING, el documento y el sueldo actual; la
-- remuneracion de la asignacion manda sobre el sueldo.
RELACION_GO AS (
    SELECT e.codDepartamento AS DPTO,
           e.ideEmpleado AS CODIGO,
           e.nomEmpleado AS PERSONAL,
           COALESCE(TRIM(pm.Documento), TRIM(e.Documento)) AS DOCUMENTO,
           TRIM(e.Area) AS AREA,
           CASE e.codDepartamentoAsignado
               WHEN ''DGO''  THEN ''GESTION DE OBRAS''
               WHEN ''DIP''  THEN ''INGENIERIA DE PROYECTOS''
               WHEN ''DPCM'' THEN ''POST CIERRE Y MANTENIMIENTO''
               WHEN ''RRCC'' THEN ''RELACIONES COMUNITARIAS''
               WHEN ''GO''   THEN ''GERENCIA DE OPERACIONES''
               ELSE TRIM(e.Departamento)
           END AS DEPARTAMENTO,
           TRIM(e.Cargo) AS PUESTO,
           CASE WHEN e.codNivel = ''SUBORDINADO'' THEN ''OPER.'' ELSE ''ADM.'' END AS TIPO,
           CAST(COALESCE(e.numRemuneracionBasica, em.SueldoActualLocal) AS decimal(14,2)) AS REMUNERACION_BASICA
    FROM EMPLEADOS e
    LEFT JOIN BD_SPRING.dbo.PersonaMast AS pm ON pm.Persona = e.ideEmpleado
    LEFT JOIN BD_SPRING.dbo.EmpleadoMast AS em ON em.Empleado = e.ideEmpleado
)'
          END
        + N'
';

    -- SQL Server solo evalua los CTE que usa el SELECT final, asi que pedir
    -- un reporte no calcula los demas.
    -- Script 68: FORCE ORDER. La consulta es tan grande que, al compilarla, SQL
    -- Server a veces se queda sin recursos (error 8623) o tarda decenas de
    -- segundos. Con el orden de las uniones fijo compila siempre y mas rapido;
    -- el resultado es el mismo.
    -- Script 70: el detalle sin filas de total cero. Se filtra aqui porque
    -- otros cuadros leen el CTE completo.
    SET @sql = @sql + N'SELECT * FROM ' + QUOTENAME(@cte)
        + CASE WHEN @cte = 'DETALLE_GASTO_PERSONAL'
               THEN N' WHERE ROUND(SUELDOS_Y_SALARIOS + GRATIFICACIONES + VACACIONES + ASIGNACION_FAMILIAR'
                    + N' + REGIMEN_DE_PRESTACIONES_DE_SALUD + SEGUROS_PARTICULARES_DE_SALUD_EPS_Y_OTROS_PARTIC'
                    + N' + COMPENSACION_POR_TIEMPO_DE_SERVICIO + OTROS, 2) <> 0'
               ELSE N'' END
        + N' ORDER BY ' + @orden + N' OPTION (FORCE ORDER);';

    EXEC sp_executesql @sql, @parametros,
        @idePeriodo = @idePeriodo, @numAnio = @numAnio, @numMes = @numMes,
        @porcDistGip = @porcDistGip, @porcDistGo = @porcDistGo,
        @porcGerenteCore1 = @porcGerenteCore1, @porcGerenteCore2 = @porcGerenteCore2,
        @porcCompensacion = @porcCompensacion,
        @porcEscDgo = @porcEscDgo, @porcEscDip = @porcEscDip, @porcEscDpcm = @porcEscDpcm, @porcEscRrcc = @porcEscRrcc,
        @porcGoDgo = @porcGoDgo, @porcGoDip = @porcGoDip, @porcGoDpcm = @porcGoDpcm, @porcGoRrcc = @porcGoRrcc,
        @horasReferencia = @horasReferencia, @flgSinValidacion = @flgSinValidacion,
        @horasMinimas = @horasMinimas;
END
GO
