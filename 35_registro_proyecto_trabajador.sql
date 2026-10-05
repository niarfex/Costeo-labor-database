/* =========================================================================
   35 - El trabajador agrega sus proyectos del periodo (correcciones 27/09)

   El listado de proyectos ya no se precarga: el trabajador elige del
   catalogo de BD_SPRING (afemst) los proyectos en los que registrara horas.
   Se guardan por periodo en registro.TMD_PERIODO_PROYECTO, sin repetidos, y
   puede quitarlos mientras el periodo siga abierto y la jefatura no haya
   validado las horas del proyecto.

   El codigo del proyecto se guarda tal como viene de afemst (12 digitos).
   Los reportes de la HU-008 cruzan por RIGHT(codProyecto, 6), asi que
   tambien reconocen este formato.

   Errores nuevos:
     50060  el proyecto no existe en el catalogo de BD_SPRING
     50061  el proyecto ya fue agregado en el periodo
     50062  el proyecto no esta agregado en el periodo
     50063  la jefatura ya valido horas del proyecto
     50064  BD_SPRING no esta disponible
     50065  el trabajador no existe (ni en el periodo, ni como usuario, ni en SPRING)
   Se reutiliza 50010 (periodo inexistente o cerrado), igual que la HU-005.

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

/* CREATE INDEX filtrado exige estas opciones activas. */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Sin proyectos repetidos por trabajador en el periodo

   Antes de crear el indice se dan de baja los repetidos que pudiera haber,
   conservando el registro mas antiguo.
   ------------------------------------------------------------------------- */

WITH repetidos AS (
    SELECT idePeriodoProyecto,
           ROW_NUMBER() OVER (PARTITION BY numAnio, numMes, ideEmpleado, codProyecto
                              ORDER BY idePeriodoProyecto) AS numOrden
    FROM registro.TMD_PERIODO_PROYECTO
    WHERE flgEstado = 1
)
UPDATE pp
SET pp.flgEstado               = 0,
    pp.fecActualizacion        = GETDATE(),
    pp.txtUsuarioActualizacion = 'SCRIPT_35'
FROM registro.TMD_PERIODO_PROYECTO pp
JOIN repetidos r ON r.idePeriodoProyecto = pp.idePeriodoProyecto
WHERE r.numOrden > 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_TMD_PERIODO_PROYECTO_EMPLEADO_PROYECTO'
                 AND object_id = OBJECT_ID('registro.TMD_PERIODO_PROYECTO'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_PERIODO_PROYECTO_EMPLEADO_PROYECTO
        ON registro.TMD_PERIODO_PROYECTO (numAnio ASC, numMes ASC, ideEmpleado ASC, codProyecto ASC)
        WHERE flgEstado = 1;
GO

/* -------------------------------------------------------------------------
   2. Catalogo de proyectos de BD_SPRING

   Es la consulta indicada por el lider. Vacio si BD_SPRING no existe, para
   que los entornos sin esa base no fallen al abrir la vista.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_Proyecto_ListarCatalogo
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT CAST(NULL AS varchar(30)) AS codProyecto, CAST(NULL AS varchar(200)) AS nomProyecto
        WHERE 1 = 0;
        RETURN;
    END

    EXEC sp_executesql N'
        SELECT TRIM(afe) AS codProyecto,
               CAST(TRIM(englishname) AS varchar(200)) AS nomProyecto
        FROM BD_SPRING.dbo.afemst
        WHERE afe IS NOT NULL
          AND englishname IS NOT NULL
        ORDER BY englishname;';
END
GO

/* -------------------------------------------------------------------------
   3. Departamento, nivel y jefatura del trabajador en el periodo

   Sin ideEmpleadoJefe la jefatura no ve al trabajador en su combo y no puede
   validar sus horas (HU-005/HU-006). Hasta ahora solo lo llenaban las semillas
   de desarrollo. Se toma de BD_SPRING, con la misma clasificacion por cargo
   del HH por proyecto (proceso.ufn_ClasificarCargo):

     subordinado o administrativo de DGO, DIP o DPCM   el jefe de su departamento
     jefe, RRCC y personal de la Gerencia (GO)          el Gerente de Operaciones activo

   Si un departamento tiene mas de un jefe activo se toma el de codigo mayor,
   que es el ingreso mas reciente. Solo completa filas sin departamento o sin
   jefe: no pisa lo que se haya cargado a mano.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_PeriodoEmpleado_CompletarOrganizacion
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
        RETURN;

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

    SELECT p.ideEmpleado, p.flgActivo, c.codDepartamento, c.codNivel
    INTO #clasificado
    FROM #personal p
    CROSS APPLY proceso.ufn_ClasificarCargo(p.Area, p.Departamento, p.Cargo) c;

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
END
GO

/* -------------------------------------------------------------------------
   4. Agregar un proyecto al periodo del trabajador

   El nombre del proyecto se toma de afemst y no del cliente. Si el
   trabajador todavia no figura en el periodo se le da de alta en
   TMD_PERIODO_EMPLEADO: sin esa fila no aparece en el combo de la jefatura
   ni puede guardar su observacion por periodo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_PeriodoProyecto_Agregar
    @numAnio     int,
    @numMes      int,
    @ideEmpleado bigint,
    @codProyecto varchar(30),
    @txtUsuario  varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    SET @codProyecto = TRIM(@codProyecto);

    DECLARE @idePeriodo bigint,
            @flgPeriodo int;

    SELECT @idePeriodo = idePeriodo, @flgPeriodo = flgEstado
    FROM registro.TMC_PERIODO
    WHERE numAnio = @numAnio AND numMes = @numMes;

    IF @idePeriodo IS NULL OR @flgPeriodo <> 1
        THROW 50010, 'El periodo no existe o se encuentra cerrado.', 1;

    IF DB_ID('BD_SPRING') IS NULL
        THROW 50064, 'No se pudo consultar el catalogo de proyectos de SPRING.', 1;

    DECLARE @nomProyecto varchar(200);

    EXEC sp_executesql N'
        SELECT TOP (1) @nombre = CAST(TRIM(englishname) AS varchar(200))
        FROM BD_SPRING.dbo.afemst
        WHERE TRIM(afe) = @codigo;',
        N'@codigo varchar(30), @nombre varchar(200) OUTPUT',
        @codigo = @codProyecto, @nombre = @nomProyecto OUTPUT;

    IF @nomProyecto IS NULL
        THROW 50060, 'El proyecto no existe en el catalogo de SPRING.', 1;

    -- Los periodos anteriores guardaban el codigo con 6 digitos y afemst lo
    -- trae con 12: se comparan por los ultimos seis, como en los reportes.
    IF EXISTS (SELECT 1 FROM registro.TMD_PERIODO_PROYECTO
               WHERE numAnio = @numAnio AND numMes = @numMes
                 AND ideEmpleado = @ideEmpleado AND RIGHT(codProyecto, 6) = RIGHT(@codProyecto, 6)
                 AND flgEstado = 1)
        THROW 50061, 'El proyecto ya fue agregado en el periodo.', 1;

    -- Nombre del trabajador: el del periodo, el de su usuario o el de SPRING.
    DECLARE @nomEmpleado varchar(200) =
        (SELECT TOP (1) nomEmpleado FROM registro.TMD_PERIODO_EMPLEADO
         WHERE numAnio = @numAnio AND numMes = @numMes
           AND ideEmpleado = @ideEmpleado AND flgEstado = 1);

    IF @nomEmpleado IS NULL
        SELECT TOP (1) @nomEmpleado = txtNombreCompleto
        FROM seguridad.TMD_PERFIL_USUARIO
        WHERE ideEmpleado = @ideEmpleado AND txtNombreCompleto IS NOT NULL
        ORDER BY flgEstado DESC, idePerfilUsuario DESC;

    IF @nomEmpleado IS NULL
        EXEC sp_executesql N'
            SELECT TOP (1) @nombre = CAST(TRIM(NombreCompleto) AS varchar(200))
            FROM BD_SPRING.dbo.PersonaMast
            WHERE Persona = @persona;',
            N'@persona bigint, @nombre varchar(200) OUTPUT',
            @persona = @ideEmpleado, @nombre = @nomEmpleado OUTPUT;

    -- Un ideEmpleado inventado no debe dar de alta a un trabajador en el periodo.
    IF @nomEmpleado IS NULL
        THROW 50065, 'El trabajador indicado no existe.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Con dos altas a la vez del mismo trabajador, el bloqueo evita dos filas.
        IF NOT EXISTS (SELECT 1 FROM registro.TMD_PERIODO_EMPLEADO WITH (UPDLOCK, HOLDLOCK)
                       WHERE numAnio = @numAnio AND numMes = @numMes
                         AND ideEmpleado = @ideEmpleado AND flgEstado = 1)
            INSERT INTO registro.TMD_PERIODO_EMPLEADO
                  (idePeriodo, numAnio, numMes, ideEmpleado, nomEmpleado,
                   flgEstado, txtUsuarioCreacion)
            VALUES (@idePeriodo, @numAnio, @numMes, @ideEmpleado, @nomEmpleado,
                   1, @txtUsuario);

        INSERT INTO registro.TMD_PERIODO_PROYECTO
              (idePeriodo, numAnio, numMes, codProyecto, nomProyecto,
               ideEmpleado, nomEmpleado, flgEstado, txtUsuarioCreacion)
        VALUES (@idePeriodo, @numAnio, @numMes, @codProyecto, @nomProyecto,
               @ideEmpleado, @nomEmpleado, 1, @txtUsuario);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    -- Fuera de la transaccion y sin propagar el error: si SPRING no responde,
    -- el proyecto ya quedo agregado y la jefatura se completa en la siguiente alta.
    BEGIN TRY
        EXEC registro.usp_PeriodoEmpleado_CompletarOrganizacion @numAnio = @numAnio, @numMes = @numMes;
    END TRY
    BEGIN CATCH
    END CATCH
END
GO

/* -------------------------------------------------------------------------
   5. Quitar un proyecto del periodo del trabajador

   Solo con el periodo abierto y sin validaciones de la jefatura sobre las
   horas del proyecto, ni por dia (HU-005) ni por mes (HU-006). Las horas
   pendientes que tuviera se dan de baja junto con el proyecto, para que no
   queden horas huerfanas en los reportes.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_PeriodoProyecto_Eliminar
    @numAnio     int,
    @numMes      int,
    @ideEmpleado bigint,
    @codProyecto varchar(30),
    @txtUsuario  varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    SET @codProyecto = TRIM(@codProyecto);

    DECLARE @flgPeriodo int =
        (SELECT flgEstado FROM registro.TMC_PERIODO
         WHERE numAnio = @numAnio AND numMes = @numMes);

    IF @flgPeriodo IS NULL OR @flgPeriodo <> 1
        THROW 50010, 'El periodo no existe o se encuentra cerrado.', 1;

    IF NOT EXISTS (SELECT 1 FROM registro.TMD_PERIODO_PROYECTO
                   WHERE numAnio = @numAnio AND numMes = @numMes
                     AND ideEmpleado = @ideEmpleado AND codProyecto = @codProyecto
                     AND flgEstado = 1)
        THROW 50062, 'El proyecto no esta agregado en el periodo.', 1;

    IF EXISTS (SELECT 1
               FROM registro.TMD_REGISTRO_HORADIA r
               JOIN registro.TMD_REGISTRO_HORADIA_VALIDACION v
                 ON v.ideRegistroHoradia = r.ideRegistroHoradia
               WHERE r.numAnio = @numAnio AND r.numMes = @numMes
                 AND r.ideEmpleado = @ideEmpleado AND r.codProyecto = @codProyecto
                 AND r.flgEstado = 1)
       OR EXISTS (SELECT 1
                  FROM registro.TMD_REGISTRO_HORAMES r
                  JOIN registro.TMD_REGISTRO_HORAMES_VALIDACION v
                    ON v.ideRegistroHorames = r.ideRegistroHorames
                  WHERE r.numAnio = @numAnio AND r.numMes = @numMes
                    AND r.ideEmpleado = @ideEmpleado AND r.codProyecto = @codProyecto
                    AND r.flgEstado = 1)
        THROW 50063, 'La jefatura ya valido horas de este proyecto; no se puede quitar.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE t
        SET t.flgEstado               = 0,
            t.fecActualizacion        = GETDATE(),
            t.txtUsuarioActualizacion = @txtUsuario
        FROM registro.TMD_REGISTRO_HORADIA_ACTTAREA t
        JOIN registro.TMD_REGISTRO_HORADIA_ACT a ON a.ideRegistroHoradiaAct = t.ideRegistroHoradiaAct
        JOIN registro.TMD_REGISTRO_HORADIA r ON r.ideRegistroHoradia = a.ideRegistroHoradia
        WHERE r.numAnio = @numAnio AND r.numMes = @numMes
          AND r.ideEmpleado = @ideEmpleado AND r.codProyecto = @codProyecto
          AND r.flgEstado = 1 AND t.flgEstado = 1;

        UPDATE a
        SET a.flgEstado               = 0,
            a.fecActualizacion        = GETDATE(),
            a.txtUsuarioActualizacion = @txtUsuario
        FROM registro.TMD_REGISTRO_HORADIA_ACT a
        JOIN registro.TMD_REGISTRO_HORADIA r ON r.ideRegistroHoradia = a.ideRegistroHoradia
        WHERE r.numAnio = @numAnio AND r.numMes = @numMes
          AND r.ideEmpleado = @ideEmpleado AND r.codProyecto = @codProyecto
          AND r.flgEstado = 1 AND a.flgEstado = 1;

        UPDATE registro.TMD_REGISTRO_HORADIA
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE numAnio = @numAnio AND numMes = @numMes
          AND ideEmpleado = @ideEmpleado AND codProyecto = @codProyecto
          AND flgEstado = 1;

        UPDATE registro.TMD_REGISTRO_HORAMES
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE numAnio = @numAnio AND numMes = @numMes
          AND ideEmpleado = @ideEmpleado AND codProyecto = @codProyecto
          AND flgEstado = 1;

        UPDATE registro.TMD_PERIODO_PROYECTO
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE numAnio = @numAnio AND numMes = @numMes
          AND ideEmpleado = @ideEmpleado AND codProyecto = @codProyecto
          AND flgEstado = 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
