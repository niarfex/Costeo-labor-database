/* =========================================================================
   42 - Correcciones de la revision contra el documento de tareas (10/10)

   1. Departamento GIP en los reportes de horas (HU-011, HU-013, HU-014).
      El personal de la Gerencia de Inversion Privada salia como OTROS y no se
      podia filtrar. Ahora el trabajador de esa gerencia queda con
      departamento GIP en su periodo, y el reporte lo muestra y lo filtra.
      Se completan tambien los periodos ya registrados (solo filas sin
      departamento).

   2. Categorizacion de proyectos: en un periodo sin categorias no se puede
      dar de alta una sin replicar antes (igual que el tipo de gasto, 50109).
      Una sola categoria en el periodo haria que el procesamiento dejara de
      usar las del periodo anterior y el resto de proyectos quedaria como
      'Categoria Desconocida'.

   Errores nuevos:
     50097  el periodo no tiene categorias y hay uno anterior: replicar antes

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Departamento del reporte, con la GIP
   ------------------------------------------------------------------------- */

CREATE OR ALTER FUNCTION registro.ufn_DepartamentoReporte (@codDepartamento varchar(10))
RETURNS TABLE
AS
RETURN
    SELECT CASE WHEN @codDepartamento IN ('DGO', 'DIP', 'DPCM', 'RRCC', 'GO', 'GIP') THEN @codDepartamento ELSE 'OTROS' END AS codDepartamento,
           CASE @codDepartamento
               WHEN 'DGO'  THEN 'DGO'
               WHEN 'DIP'  THEN 'DIP'
               WHEN 'DPCM' THEN 'POST CIERRE'
               WHEN 'RRCC' THEN 'RELACIONES COMUNITARIAS'
               WHEN 'GO'   THEN 'GERENCIA DE OPERACIONES'
               WHEN 'GIP'  THEN 'GIP'
               ELSE 'OTROS'
           END AS nomDepartamento,
           CASE @codDepartamento
               WHEN 'DGO' THEN 1 WHEN 'DIP' THEN 2 WHEN 'DPCM' THEN 3 WHEN 'RRCC' THEN 4 WHEN 'GO' THEN 5
               WHEN 'GIP' THEN 6
               ELSE 7
           END AS numOrden;
GO

/* -------------------------------------------------------------------------
   2. El personal de la GIP queda con su departamento en el periodo
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
    WHERE pe.numAnio = @numAnio AND pe.numMes = @numMes AND pe.flgEstado = 1
      AND pe.codDepartamento IS NULL
      AND p.Area COLLATE Latin1_General_CI_AI = 'GERENCIA DE INVERSION PRIVADA';
END
GO

/* Periodos ya registrados: se completan los trabajadores de la GIP que
   quedaron sin departamento. Sin BD_SPRING no hace nada. */
IF DB_ID('BD_SPRING') IS NOT NULL
BEGIN
    EXEC sp_executesql N'
        UPDATE pe
        SET pe.codDepartamento = ''GIP'',
            pe.nomDepartamento = ''GERENCIA DE INVERSION PRIVADA''
        FROM registro.TMD_PERIODO_EMPLEADO pe
        JOIN BD_SPRING.dbo.EmpleadoMast em ON em.Empleado = pe.ideEmpleado
        JOIN BD_SPRING.dbo.HR_Division hrdiv ON hrdiv.Division = em.Division
        WHERE pe.flgEstado = 1
          AND pe.codDepartamento IS NULL
          AND TRIM(hrdiv.DescripcionLarga) COLLATE Latin1_General_CI_AI = ''GERENCIA DE INVERSION PRIVADA'';';
END
GO

/* -------------------------------------------------------------------------
   3. Categorizacion: alta en un periodo vacio, solo despues de replicar
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_CategoriaProyecto_Guardar
    @ideCategoriaProyecto bigint = NULL,
    @numAnio      int,
    @numMes       int,
    @codCategoria varchar(30),
    @proyectos    proceso.TYPE_CATEGORIA_PROYECTO_DETALLE READONLY,
    @txtUsuario   varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @codCategoria = UPPER(TRIM(@codCategoria));

    IF @ideCategoriaProyecto IS NOT NULL
    BEGIN
        -- En la edicion el periodo es el de la categoria, no el que mande el cliente.
        SELECT @numAnio = numAnio, @numMes = numMes
        FROM proceso.TMC_CATEGORIA_PROYECTO
        WHERE ideCategoriaProyecto = @ideCategoriaProyecto AND flgEstado = 1;

        IF @@ROWCOUNT = 0
            THROW 50093, 'La categoria indicada no existe o fue eliminada.', 1;
    END

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50090, 'El periodo esta cerrado: su categorizacion de proyectos no se puede modificar.', 1;

    -- Es el valor que el procesamiento guarda como categoria (FA, PAR...) y la
    -- fuente que muestran los reportes: letras, numeros, espacios y guion.
    IF ISNULL(@codCategoria, '') = ''
        THROW 50094, 'El nombre de la categoria es obligatorio.', 1;

    IF @codCategoria COLLATE Latin1_General_BIN LIKE '%[^A-Z0-9 -]%'
        THROW 50094, 'El nombre de la categoria solo admite letras, numeros, espacios y guion.', 1;

    IF NOT EXISTS (SELECT 1 FROM @proyectos)
        THROW 50094, 'La categoria debe tener al menos un proyecto.', 1;

    -- Un periodo sin categorias usa las del ultimo periodo anterior que las
    -- tenga. Si aqui se diera de alta una sola, el procesamiento dejaria de
    -- usar las anteriores y el resto de proyectos quedaria como 'Categoria
    -- Desconocida'. Se parte replicando, como en el tipo de gasto (50109).
    IF @ideCategoriaProyecto IS NULL
       AND NOT EXISTS (SELECT 1 FROM proceso.TMC_CATEGORIA_PROYECTO
                       WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1)
       AND EXISTS (SELECT 1 FROM proceso.TMC_CATEGORIA_PROYECTO
                   WHERE flgEstado = 1 AND numAnio * 100 + numMes < @numAnio * 100 + @numMes)
        THROW 50097, 'El periodo aun no tiene categorias: use Replicar del periodo anterior antes de crear una nueva.', 1;

    IF EXISTS (SELECT 1 FROM proceso.TMC_CATEGORIA_PROYECTO
               WHERE numAnio = @numAnio AND numMes = @numMes AND codCategoria = @codCategoria
                 AND flgEstado = 1
                 AND ideCategoriaProyecto <> ISNULL(@ideCategoriaProyecto, 0))
        THROW 50091, 'Ya existe una categoria con ese nombre en el periodo.', 1;

    -- Se eligen de los activos del periodo. Los que la categoria ya tenia se
    -- conservan aunque hayan dejado de estar activos (por ejemplo, al replicar).
    DECLARE @inactivo varchar(200) =
        (SELECT TOP (1) CONCAT('El proyecto ', p.codProyecto, ' no esta activo para Costo Labor en el periodo.')
         FROM @proyectos p
         WHERE NOT EXISTS (SELECT 1 FROM proceso.TMD_ESTADO_PROYECTO e
                           WHERE e.numAnio = @numAnio AND e.numMes = @numMes AND e.codProyecto = p.codProyecto
                             AND e.flgEstado = 1 AND e.flgActivoCostoLabor = 1)
           AND NOT EXISTS (SELECT 1 FROM proceso.TMD_CATEGORIA_PROYECTO_DETALLE d
                           WHERE d.ideCategoriaProyecto = @ideCategoriaProyecto
                             AND d.codProyecto = p.codProyecto AND d.flgEstado = 1));

    IF @inactivo IS NOT NULL
        THROW 50095, @inactivo, 1;

    -- Un proyecto en dos categorias quedaria clasificado al azar.
    DECLARE @repetido varchar(200) =
        (SELECT TOP (1) CONCAT('El proyecto ', p.codProyecto, ' ya esta en la categoria ', c.codCategoria, '.')
         FROM @proyectos p
         JOIN proceso.TMD_CATEGORIA_PROYECTO_DETALLE d
           ON d.codProyecto = p.codProyecto AND d.flgEstado = 1
         JOIN proceso.TMC_CATEGORIA_PROYECTO c
           ON c.ideCategoriaProyecto = d.ideCategoriaProyecto AND c.flgEstado = 1
         WHERE c.numAnio = @numAnio AND c.numMes = @numMes
           AND c.ideCategoriaProyecto <> ISNULL(@ideCategoriaProyecto, 0));

    IF @repetido IS NOT NULL
        THROW 50092, @repetido, 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- El nombre que tenia cada proyecto, para no perderlo al reemplazar el detalle.
        DECLARE @nombres TABLE (codProyecto varchar(30) PRIMARY KEY, nomProyecto varchar(200));

        IF @ideCategoriaProyecto IS NULL
        BEGIN
            INSERT INTO proceso.TMC_CATEGORIA_PROYECTO (numAnio, numMes, codCategoria, flgEstado, txtUsuarioCreacion)
            VALUES (@numAnio, @numMes, @codCategoria, 1, @txtUsuario);
            SET @ideCategoriaProyecto = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE proceso.TMC_CATEGORIA_PROYECTO
            SET codCategoria = @codCategoria,
                fecActualizacion = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideCategoriaProyecto = @ideCategoriaProyecto;

            INSERT INTO @nombres (codProyecto, nomProyecto)
            SELECT codProyecto, MAX(nomProyecto)
            FROM proceso.TMD_CATEGORIA_PROYECTO_DETALLE
            WHERE ideCategoriaProyecto = @ideCategoriaProyecto AND flgEstado = 1
            GROUP BY codProyecto;

            UPDATE proceso.TMD_CATEGORIA_PROYECTO_DETALLE
            SET flgEstado = 0,
                fecActualizacion = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideCategoriaProyecto = @ideCategoriaProyecto AND flgEstado = 1;
        END

        INSERT INTO proceso.TMD_CATEGORIA_PROYECTO_DETALLE
              (ideCategoriaProyecto, numAnio, numMes, codProyecto, nomProyecto, flgEstado, txtUsuarioCreacion)
        SELECT @ideCategoriaProyecto, @numAnio, @numMes, p.codProyecto,
               COALESCE(e.nomProyecto, n.nomProyecto), 1, @txtUsuario
        FROM @proyectos p
        LEFT JOIN proceso.TMD_ESTADO_PROYECTO e
               ON e.numAnio = @numAnio AND e.numMes = @numMes AND e.codProyecto = p.codProyecto AND e.flgEstado = 1
        LEFT JOIN @nombres n ON n.codProyecto = p.codProyecto;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @ideCategoriaProyecto AS ideCategoriaProyecto;
END
GO
