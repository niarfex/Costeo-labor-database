/* =========================================================================
   80 - Registro de horas por mes: solo personal de Operaciones y con la
        asignacion de personal del Contador

   Pedido de Efrain (26/11): en el registro de horas por mes aparecian, sin
   departamento, trabajadores que en SPRING no son de la Gerencia de
   Operaciones (TORNERO YAYA en Administracion y Finanzas, VALVERDE OBREGON
   en Gerencia General). La grilla lista ahora solo los departamentos de
   Operaciones (DGO, DIP, DPCM, RRCC y GO), y si el Contador registro una
   asignacion de personal para la persona en el periodo, el registro de horas
   la usa, igual que el calculo del costo labor (script 71).

   1. registro.TMD_PERIODO_EMPLEADO: columna flgAsignacion, marca a quien se
      clasifico con una asignacion, para devolverlo a SPRING si se quita.
   2. registro.usp_PeriodoEmpleado_CompletarOrganizacion (version del script
      42): departamento, nivel y jefatura con la asignacion del periodo.
   3. Grilla mensual (versiones del script 52): ListarTrabajadores y
      ListarHoras, solo departamentos de Operaciones. ListarDisponibles
      ("Agregar trabajador"), solo personal de Operaciones segun SPRING o la
      asignacion.
   4. Asignacion de personal (Guardar y Replicar del script 71, Eliminar del
      47): al terminar actualizan el registro de horas del periodo.
   5. Periodos no cerrados con asignaciones: se recalculan al aplicar el
      script.

   El registro por dia no cambia: cada trabajador sigue viendo sus horas.

   Requiere los scripts 52 y 71.

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

IF COL_LENGTH('proceso.TMD_ASIGNACION_AREA', 'codDepartamento') IS NULL
    THROW 50158, 'Falta codDepartamento en proceso.TMD_ASIGNACION_AREA: ejecute antes el script 71.', 1;
GO

IF COL_LENGTH('registro.TMD_PERIODO_EMPLEADO', 'flgAsignacion') IS NULL
    ALTER TABLE registro.TMD_PERIODO_EMPLEADO
        ADD flgAsignacion bit NOT NULL CONSTRAINT DF_TMD_PERIODO_EMPLEADO_flgAsignacion DEFAULT (0);
GO

/* -------------------------------------------------------------------------
   1. Departamento, nivel y jefatura del trabajador en el periodo

   Version del script 42 con la asignacion del Contador. Igual que el calculo
   del costo labor (script 71, EMPLEADOS_PERIODO): el area y el puesto de la
   asignacion reemplazan a los de SPRING antes de clasificar, y su
   departamento y nivel mandan sobre los de la clasificacion.

   Quien tiene asignacion en el periodo se recalcula siempre (flgAsignacion =
   1); quien la tenia y ya no, vuelve a lo que diga SPRING. El resto, como
   antes: solo se completa lo que falta.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_PeriodoEmpleado_CompletarOrganizacion
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
        RETURN;

    -- Asignaciones vigentes del periodo.
    SELECT idePersona, nomArea, codDepartamento, codNivel, txtPuesto
    INTO #asignacion
    FROM proceso.TMD_ASIGNACION_AREA
    WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1;

    -- Se vuelven a calcular quienes tienen asignacion y quienes la perdieron.
    UPDATE pe
    SET pe.codDepartamento = NULL,
        pe.nomDepartamento = NULL,
        pe.codNivel        = NULL,
        pe.ideEmpleadoJefe = NULL,
        pe.flgAsignacion   = CASE WHEN a.idePersona IS NULL THEN 0 ELSE 1 END
    FROM registro.TMD_PERIODO_EMPLEADO pe
    LEFT JOIN #asignacion a ON a.idePersona = pe.ideEmpleado
    WHERE pe.numAnio = @numAnio AND pe.numMes = @numMes AND pe.flgEstado = 1
      AND (a.idePersona IS NOT NULL OR pe.flgAsignacion = 1);

    CREATE TABLE #personal (
        ideEmpleado  bigint PRIMARY KEY,
        flgActivo    bit,
        Area         varchar(200),
        Departamento varchar(200),
        Cargo        varchar(200)
    );

    INSERT INTO #personal (ideEmpleado, flgActivo, Area, Departamento, Cargo)
    EXEC sp_executesql N'
        SELECT em.Empleado,
               CASE WHEN em.Estado = ''A'' THEN 1 ELSE 0 END,
               TRIM(hrdiv.DescripcionLarga),
               TRIM(hrdep.Descripcion),
               TRIM(hre.Descripcion)
        FROM BD_SPRING.dbo.EmpleadoMast AS em
        LEFT JOIN BD_SPRING.dbo.HR_PuestoEmpresa AS hre ON hre.CodigoPuesto = em.CodigoCargo
        LEFT JOIN BD_SPRING.dbo.HR_Departamento AS hrdep ON hrdep.Departamento = em.DepartamentoOperacional
        LEFT JOIN BD_SPRING.dbo.HR_Division AS hrdiv ON hrdiv.Division = em.Division;';

    -- Script 80: con la asignacion del periodo, como en el calculo del costo labor.
    SELECT p.ideEmpleado, p.flgActivo,
           COALESCE(a.codDepartamento, c.codDepartamento) AS codDepartamento,
           COALESCE(a.codNivel, c.codNivel) AS codNivel
    INTO #clasificado
    FROM #personal p
    LEFT JOIN #asignacion a ON a.idePersona = p.ideEmpleado
    CROSS APPLY proceso.ufn_ClasificarCargo(COALESCE(a.nomArea, p.Area), p.Departamento,
                                            COALESCE(a.txtPuesto, p.Cargo)) c;

    -- Por el cargo y no por el area: el encargado de la gerencia puede figurar
    -- en otra (en SPRING, GERENTE DE OPERACIONES (E) - JEFE DE OPMC esta en
    -- Planeamiento y Mejora Continua).
    DECLARE @gerente bigint =
        (SELECT TOP (1) ideEmpleado FROM #personal
         WHERE flgActivo = 1 AND Cargo COLLATE Latin1_General_CI_AI LIKE 'GERENTE DE OPERACIONES%'
         ORDER BY ideEmpleado DESC);

    WITH jefes AS (
        SELECT codDepartamento, MAX(ideEmpleado) AS ideJefe
        FROM #clasificado
        WHERE flgActivo = 1 AND codNivel = 'JEFE'
        GROUP BY codDepartamento
    ),
    organizacion AS (
        SELECT c.ideEmpleado, c.codDepartamento,
               CASE c.codDepartamento
                   WHEN 'DGO'  THEN 'GESTION DE OBRAS'
                   WHEN 'DIP'  THEN 'INGENIERIA DE PROYECTOS'
                   WHEN 'DPCM' THEN 'POST CIERRE Y MANTENIMIENTO'
                   WHEN 'RRCC' THEN 'RELACIONES COMUNITARIAS'
                   ELSE 'GERENCIA DE OPERACIONES'
               END AS nomDepartamento,
               -- El CHECK de la tabla solo admite estos tres niveles.
               CASE WHEN c.codNivel IN ('JEFE', 'ADMINISTRATIVO', 'SUBORDINADO') THEN c.codNivel END AS codNivel,
               CASE
                   WHEN c.codNivel = 'GERENTE' THEN NULL
                   WHEN c.codNivel IN ('SUBORDINADO', 'ADMINISTRATIVO')
                        AND c.codDepartamento IN ('DGO', 'DIP', 'DPCM')
                        THEN COALESCE(j.ideJefe, @gerente)
                   ELSE @gerente
               END AS ideEmpleadoJefe
        FROM #clasificado c
        LEFT JOIN jefes j ON j.codDepartamento = c.codDepartamento
    )
    UPDATE pe
    SET pe.codDepartamento = COALESCE(pe.codDepartamento, o.codDepartamento),
        pe.nomDepartamento = COALESCE(pe.nomDepartamento, o.nomDepartamento),
        pe.codNivel        = COALESCE(pe.codNivel, o.codNivel),
        -- Nadie es su propio jefe.
        pe.ideEmpleadoJefe = COALESCE(pe.ideEmpleadoJefe, NULLIF(o.ideEmpleadoJefe, pe.ideEmpleado))
    FROM registro.TMD_PERIODO_EMPLEADO pe
    JOIN organizacion o ON o.ideEmpleado = pe.ideEmpleado
    WHERE pe.numAnio = @numAnio AND pe.numMes = @numMes AND pe.flgEstado = 1
      AND (pe.codDepartamento IS NULL OR pe.ideEmpleadoJefe IS NULL);

    -- La Gerencia de Inversion Privada no es de la Gerencia de Operaciones
    -- (ufn_ClasificarCargo no la clasifica, y asi debe seguir para el HH por
    -- proyecto), pero los reportes de horas la muestran como departamento
    -- propio (HU-011, HU-013, HU-014). Solo se completa el departamento: la
    -- jefatura y el nivel no cambian.
    UPDATE pe
    SET pe.codDepartamento = 'GIP',
        pe.nomDepartamento = 'GERENCIA DE INVERSION PRIVADA'
    FROM registro.TMD_PERIODO_EMPLEADO pe
    JOIN #personal p ON p.ideEmpleado = pe.ideEmpleado
    LEFT JOIN #asignacion a ON a.idePersona = pe.ideEmpleado
    WHERE pe.numAnio = @numAnio AND pe.numMes = @numMes AND pe.flgEstado = 1
      AND pe.codDepartamento IS NULL
      AND COALESCE(a.nomArea, p.Area) COLLATE Latin1_General_CI_AI = 'GERENCIA DE INVERSION PRIVADA';
END
GO

/* 3. Grilla mensual */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarTrabajadores
    @numAnio               int,
    @numMes                int,
    @ideEmpleadoJefe       bigint = NULL,
    @ideEmpleado           bigint = NULL,
    @txtUsuarioResponsable varchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  pe.ideEmpleado,
            pe.nomEmpleado,
            pe.codDepartamento,
            pe.nomDepartamento,
            pe.codNivel,
            pe.txtObservaciones,
            e.codEstadoValidacion
    FROM registro.TMD_PERIODO_EMPLEADO pe
    LEFT JOIN registro.VW_REGISTRO_HORAMES_ESTADO e
           ON e.ideEmpleado = pe.ideEmpleado
          AND e.numAnio = pe.numAnio
          AND e.numMes  = pe.numMes
    WHERE pe.numAnio = @numAnio
      AND pe.numMes  = @numMes
      AND pe.flgEstado = 1
      -- Script 80: solo los departamentos de la Gerencia de Operaciones.
      AND pe.codDepartamento IN ('DGO', 'DIP', 'DPCM', 'RRCC', 'GO')
      -- La jefatura tambien se ve a si misma: el prototipo la muestra como
      -- primera fila de su departamento, aunque no dependa de nadie.
      AND (@ideEmpleadoJefe IS NULL
           OR pe.ideEmpleadoJefe = @ideEmpleadoJefe
           OR pe.ideEmpleado = @ideEmpleadoJefe)
      AND (@ideEmpleado IS NULL OR pe.ideEmpleado = @ideEmpleado)
      -- El responsable de registro ve solo a los trabajadores que agrego al periodo.
      AND (@txtUsuarioResponsable IS NULL
           OR EXISTS (SELECT 1 FROM registro.TMD_PERIODO_EMPLEADO_RESPONSABLE a
                      WHERE a.numAnio = pe.numAnio AND a.numMes = pe.numMes
                        AND a.ideEmpleado = pe.ideEmpleado AND a.flgEstado = 1
                        AND a.txtUsuarioResponsable = @txtUsuarioResponsable))
    ORDER BY pe.codDepartamento,
             CASE pe.codNivel WHEN 'JEFE' THEN 1 WHEN 'ADMINISTRATIVO' THEN 2 ELSE 3 END,
             pe.nomEmpleado;
END
GO

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarHoras
    @numAnio               int,
    @numMes                int,
    @ideEmpleadoJefe       bigint = NULL,
    @ideEmpleado           bigint = NULL,
    @txtUsuarioResponsable varchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  r.ideRegistroHorames,
            r.ideEmpleado,
            r.codProyecto,
            r.numHoras
    FROM registro.TMD_REGISTRO_HORAMES r
    JOIN registro.TMD_PERIODO_EMPLEADO pe
      ON pe.ideEmpleado = r.ideEmpleado
     AND pe.numAnio = r.numAnio
     AND pe.numMes  = r.numMes
     AND pe.flgEstado = 1
     -- Script 80: las de quienes lista la grilla.
     AND pe.codDepartamento IN ('DGO', 'DIP', 'DPCM', 'RRCC', 'GO')
    WHERE r.numAnio = @numAnio
      AND r.numMes  = @numMes
      AND r.flgEstado = 1
      AND (@ideEmpleadoJefe IS NULL
           OR pe.ideEmpleadoJefe = @ideEmpleadoJefe
           OR pe.ideEmpleado = @ideEmpleadoJefe)
      AND (@ideEmpleado IS NULL OR pe.ideEmpleado = @ideEmpleado)
      AND (@txtUsuarioResponsable IS NULL
           OR EXISTS (SELECT 1 FROM registro.TMD_PERIODO_EMPLEADO_RESPONSABLE a
                      WHERE a.numAnio = pe.numAnio AND a.numMes = pe.numMes
                        AND a.ideEmpleado = pe.ideEmpleado AND a.flgEstado = 1
                        AND a.txtUsuarioResponsable = @txtUsuarioResponsable))
    ORDER BY r.ideEmpleado, r.codProyecto;
END
GO

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarDisponibles
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT CAST(NULL AS bigint) AS idePersona, CAST(NULL AS varchar(200)) AS txtNombreCompleto,
               CAST(NULL AS varchar(20)) AS Documento, CAST(NULL AS varchar(200)) AS Area,
               CAST(NULL AS varchar(200)) AS Departamento, CAST(NULL AS varchar(200)) AS Cargo
        WHERE 1 = 0;
        RETURN;
    END

    EXEC sp_executesql N'
        SELECT DISTINCT
            CAST(pm.Persona AS bigint) AS idePersona,
            TRIM(pm.NombreCompleto) AS txtNombreCompleto,
            TRIM(pm.Documento) AS Documento,
            hrdiv.DescripcionLarga AS Area,
            hrdep.Descripcion AS Departamento,
            hre.Descripcion AS Cargo
        FROM BD_SPRING.dbo.PersonaMast AS pm
        LEFT JOIN BD_SPRING.dbo.EmpleadoMast AS em ON em.Empleado = pm.Persona
        LEFT JOIN BD_SPRING.dbo.HR_PuestoEmpresa AS hre ON hre.CodigoPuesto = em.CodigoCargo
        LEFT JOIN BD_SPRING.dbo.HR_Departamento AS hrdep ON hrdep.Departamento = em.DepartamentoOperacional
        LEFT JOIN BD_SPRING.dbo.HR_Division AS hrdiv ON hrdiv.Division = em.Division
        -- Script 80: solo personal de Operaciones, con la asignacion del Contador si la hay.
        LEFT JOIN proceso.TMD_ASIGNACION_AREA AS a
               ON a.numAnio = @anio AND a.numMes = @mes AND a.idePersona = pm.Persona AND a.flgEstado = 1
        CROSS APPLY proceso.ufn_ClasificarCargo(COALESCE(a.nomArea, TRIM(hrdiv.DescripcionLarga)), TRIM(hrdep.Descripcion),
                                                COALESCE(a.txtPuesto, TRIM(hre.Descripcion))) c
        WHERE em.Empleado IS NOT NULL
          AND COALESCE(a.codDepartamento, c.codDepartamento) IN (''DGO'', ''DIP'', ''DPCM'', ''RRCC'', ''GO'')
          AND (em.FechaCese IS NULL
               OR @anio * 100 + @mes <= YEAR(em.FechaCese) * 100 + MONTH(em.FechaCese))
          AND NOT EXISTS (SELECT 1 FROM registro.TMD_PERIODO_EMPLEADO_RESPONSABLE r
                          WHERE r.numAnio = @anio AND r.numMes = @mes
                            AND r.ideEmpleado = pm.Persona AND r.flgEstado = 1)
        ORDER BY txtNombreCompleto;',
        N'@anio int, @mes int', @anio = @numAnio, @mes = @numMes;
END
GO

/* 4. Asignacion de personal */

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

    -- Script 80: el registro de horas del periodo toma la asignacion al momento.
    BEGIN TRY
        EXEC registro.usp_PeriodoEmpleado_CompletarOrganizacion @numAnio = @numAnio, @numMes = @numMes;
    END TRY
    BEGIN CATCH
    END CATCH

    SELECT @ideAsignacionArea AS ideAsignacionArea;
END
GO

CREATE OR ALTER PROCEDURE proceso.usp_AsignacionArea_Eliminar
    @ideAsignacionArea bigint,
    @txtUsuario        varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @numAnio int, @numMes int;
    SELECT @numAnio = numAnio, @numMes = numMes
    FROM proceso.TMD_ASIGNACION_AREA
    WHERE ideAsignacionArea = @ideAsignacionArea AND flgEstado = 1;

    IF @numAnio IS NULL
        THROW 50125, 'La asignacion indicada no existe.', 1;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50120, 'El periodo esta cerrado: sus asignaciones de personal no se pueden modificar.', 1;

    UPDATE proceso.TMD_ASIGNACION_AREA
    SET flgEstado = 0,
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE ideAsignacionArea = @ideAsignacionArea;

    -- Script 80: el registro de horas del periodo toma la asignacion al momento.
    BEGIN TRY
        EXEC registro.usp_PeriodoEmpleado_CompletarOrganizacion @numAnio = @numAnio, @numMes = @numMes;
    END TRY
    BEGIN CATCH
    END CATCH
END
GO

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

    -- Script 80: el registro de horas del periodo toma la asignacion al momento.
    BEGIN TRY
        EXEC registro.usp_PeriodoEmpleado_CompletarOrganizacion @numAnio = @numAnio, @numMes = @numMes;
    END TRY
    BEGIN CATCH
    END CATCH

    SELECT @numAnioOrigen AS numAnioOrigen, @numMesOrigen AS numMesOrigen, @numCopiadas AS numCopiadas;
END
GO

/* -------------------------------------------------------------------------
   5. Periodos no cerrados que ya tienen asignaciones
   ------------------------------------------------------------------------- */

DECLARE @anio int, @mes int;
DECLARE periodos CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT a.numAnio, a.numMes
    FROM proceso.TMD_ASIGNACION_AREA a
    WHERE a.flgEstado = 1
      AND NOT EXISTS (SELECT 1 FROM registro.TMC_PERIODO p
                      WHERE p.numAnio = a.numAnio AND p.numMes = a.numMes AND p.flgEstado = 2);
OPEN periodos;
FETCH NEXT FROM periodos INTO @anio, @mes;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC registro.usp_PeriodoEmpleado_CompletarOrganizacion @numAnio = @anio, @numMes = @mes;
    FETCH NEXT FROM periodos INTO @anio, @mes;
END
CLOSE periodos;
DEALLOCATE periodos;
GO
