/* =========================================================================
   52 - Registro de horas por mes: el responsable de registro agrega a sus
   trabajadores del periodo

   El responsable de registro arma su grilla mensual agregando trabajadores
   de SPRING por periodo. Al agregar a uno lo toma para si: en ese periodo
   ningun otro responsable lo ve, lo agrega ni le registra horas. La jefatura
   y el propio trabajador lo siguen viendo como antes (jefatura y alcance
   propio no cambian).

   Personal que se puede agregar (registro.usp_RegistroHoraMes_ListarDisponibles):
   empleados de SPRING sin fecha de cese o cuyo mes de cese no es anterior al
   periodo. Anio y mes se comparan juntos (anio * 100 + mes): comparados por
   separado, un cese en marzo del anio siguiente quedaria fuera de octubre, y
   un cese NULL (casi todo el personal en actividad) descartaria a la persona.
   Quien ya esta agregado al periodo por cualquier responsable no aparece.

   Agregar da de alta al trabajador en registro.TMD_PERIODO_EMPLEADO si aun no
   figura, y completa su departamento, nivel y jefatura desde SPRING. Asi la
   jefatura lo ve para validar sus horas y los reportes de horas (HU-011,
   HU-013, HU-014) lo ubican en su departamento.

   Quitar solo procede mientras el trabajador no tenga horas en el periodo:
   esas horas son las que valida la jefatura, las que lee el costo labor y
   las que muestran los reportes. Borrarlas al quitar podria eliminar horas
   que el trabajador registro por su cuenta, y dejarlas sin responsable las
   dejaria sin nadie que las corrija. Si el alta en el periodo la hizo la
   asignacion y nada mas lo retiene ahi, el trabajador sale del periodo.

   Grilla mensual (ultimas versiones del script 25):
     usp_RegistroHoraMes_ListarTrabajadores,
     usp_RegistroHoraMes_ListarHoras      aceptan @txtUsuarioResponsable: el
                                          responsable ve solo a los suyos.
     usp_RegistroHoraMes_ListarProyectos  ademas, las columnas son los
                                          proyectos activos para Costo Labor
                                          del periodo, mas los que el
                                          trabajador agrego y los que ya
                                          tienen horas (sus horas nunca se
                                          ocultan). Para la jefatura, que solo
                                          valida, siguen siendo los proyectos
                                          de su equipo.
   Los parametros nuevos son opcionales: con NULL se comportan como antes.

   Horas ya registradas (seccion 8): en los periodos abiertos, el trabajador
   cuyas horas por mes registro un solo responsable de registro queda
   agregado a ese responsable, para que sus horas no queden ocultas. Si las
   registraron dos o mas, se listan para resolverlos a mano.

   Personal de la asignacion de areas (seccion 9): usa la misma consulta de
   personal que este registro, asi que registro.usp_PersonalSpring_ListarPeriodo
   (script 47) pasa a la misma condicion de cese.

   Errores nuevos:
     50138  el periodo no existe, esta cerrado o es posterior al mes en curso
     50139  el trabajador no figura en SPRING o ceso antes del periodo
     50140  el trabajador ya fue agregado al periodo
     50141  el trabajador no esta agregado al registro del responsable
     50142  el trabajador ya tiene horas en el periodo: no se puede quitar

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

/* Obligatorio: las tablas con indices filtrados rechazan cualquier DML y
   cualquier procedimiento compilado sin estas opciones. */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Trabajadores de cada responsable por periodo

   El indice unico filtrado es el que garantiza la exclusividad, tambien
   cuando dos responsables agregan a la misma persona a la vez.
   flgAltaPeriodo indica si la asignacion dio de alta al trabajador en
   TMD_PERIODO_EMPLEADO, para deshacer ese alta al quitarlo.
   ------------------------------------------------------------------------- */

IF OBJECT_ID('registro.TMD_PERIODO_EMPLEADO_RESPONSABLE') IS NULL
BEGIN
    CREATE TABLE registro.TMD_PERIODO_EMPLEADO_RESPONSABLE(
        idePeriodoEmpleadoResponsable bigint IDENTITY(1,1) NOT NULL,
        idePeriodo bigint NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        ideEmpleado bigint NOT NULL,
        nomEmpleado varchar(200) NOT NULL,
        txtDocumento varchar(20) NULL,
        txtUsuarioResponsable varchar(100) NOT NULL,
        flgAltaPeriodo bit NOT NULL CONSTRAINT DF_TMD_PERIODO_EMPLEADO_RESPONSABLE_flgAltaPeriodo DEFAULT (0),
        flgEstado int NOT NULL CONSTRAINT DF_TMD_PERIODO_EMPLEADO_RESPONSABLE_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_PERIODO_EMPLEADO_RESPONSABLE_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMD_PERIODO_EMPLEADO_RESPONSABLE PRIMARY KEY CLUSTERED (idePeriodoEmpleadoResponsable ASC),
        CONSTRAINT FK_TMD_PERIODO_EMPLEADO_RESPONSABLE_PERIODO FOREIGN KEY (idePeriodo)
            REFERENCES registro.TMC_PERIODO (idePeriodo)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_TMD_PERIODO_EMPLEADO_RESPONSABLE_PERIODO'
                 AND object_id = OBJECT_ID('registro.TMD_PERIODO_EMPLEADO_RESPONSABLE'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_PERIODO_EMPLEADO_RESPONSABLE_PERIODO
        ON registro.TMD_PERIODO_EMPLEADO_RESPONSABLE (numAnio ASC, numMes ASC, ideEmpleado ASC)
        WHERE flgEstado = 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_TMD_PERIODO_EMPLEADO_RESPONSABLE_USUARIO'
                 AND object_id = OBJECT_ID('registro.TMD_PERIODO_EMPLEADO_RESPONSABLE'))
    CREATE NONCLUSTERED INDEX IX_TMD_PERIODO_EMPLEADO_RESPONSABLE_USUARIO
        ON registro.TMD_PERIODO_EMPLEADO_RESPONSABLE (numAnio ASC, numMes ASC, txtUsuarioResponsable ASC)
        INCLUDE (ideEmpleado)
        WHERE flgEstado = 1;
GO

/* -------------------------------------------------------------------------
   2. Personal de SPRING que se puede agregar al periodo

   Columnas y cruces de la consulta de referencia. Se exige la fila de
   EmpleadoMast: con la condicion de cese corregida, un LEFT JOIN sin ella
   traeria a toda PersonaMast (proveedores y terceros incluidos). Vacio si
   BD_SPRING no esta disponible.
   ------------------------------------------------------------------------- */

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
        WHERE em.Empleado IS NOT NULL
          AND (em.FechaCese IS NULL
               OR @anio * 100 + @mes <= YEAR(em.FechaCese) * 100 + MONTH(em.FechaCese))
          AND NOT EXISTS (SELECT 1 FROM registro.TMD_PERIODO_EMPLEADO_RESPONSABLE r
                          WHERE r.numAnio = @anio AND r.numMes = @mes
                            AND r.ideEmpleado = pm.Persona AND r.flgEstado = 1)
        ORDER BY txtNombreCompleto;',
        N'@anio int, @mes int', @anio = @numAnio, @mes = @numMes;
END
GO

/* -------------------------------------------------------------------------
   3. Agregar un trabajador al registro del responsable

   Devuelve el identificador de la asignacion y el nombre del trabajador.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_AgregarTrabajador
    @numAnio     int,
    @numMes      int,
    @ideEmpleado bigint,
    @txtUsuario  varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idePeriodo bigint,
            @flgPeriodo int;

    SELECT @idePeriodo = idePeriodo, @flgPeriodo = flgEstado
    FROM registro.TMC_PERIODO
    WHERE numAnio = @numAnio AND numMes = @numMes;

    IF @idePeriodo IS NULL OR @flgPeriodo <> 1
        THROW 50138, 'El periodo no existe o se encuentra cerrado.', 1;

    -- Mismo limite que el guardado de horas: no se registra en meses futuros.
    IF DATEFROMPARTS(@numAnio, @numMes, 1) > DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
        THROW 50138, 'No se agregan trabajadores en un periodo posterior al mes en curso.', 1;

    IF DB_ID('BD_SPRING') IS NULL
        THROW 50139, 'No se pudo consultar el personal de SPRING.', 1;

    DECLARE @nomEmpleado  varchar(200),
            @txtDocumento varchar(20);

    -- La misma condicion del listado: el cliente no decide a quien se puede agregar.
    EXEC sp_executesql N'
        SELECT TOP (1) @nombre = CAST(TRIM(pm.NombreCompleto) AS varchar(200)),
                       @documento = LEFT(TRIM(pm.Documento), 20)
        FROM BD_SPRING.dbo.PersonaMast AS pm
        JOIN BD_SPRING.dbo.EmpleadoMast AS em ON em.Empleado = pm.Persona
        WHERE pm.Persona = @persona
          AND (em.FechaCese IS NULL
               OR @anio * 100 + @mes <= YEAR(em.FechaCese) * 100 + MONTH(em.FechaCese));',
        N'@persona bigint, @anio int, @mes int, @nombre varchar(200) OUTPUT, @documento varchar(20) OUTPUT',
        @persona = @ideEmpleado, @anio = @numAnio, @mes = @numMes,
        @nombre = @nomEmpleado OUTPUT, @documento = @txtDocumento OUTPUT;

    IF @nomEmpleado IS NULL
        THROW 50139, 'El trabajador no figura en SPRING o su cese es anterior al periodo.', 1;

    DECLARE @responsable varchar(100) =
        (SELECT txtUsuarioResponsable FROM registro.TMD_PERIODO_EMPLEADO_RESPONSABLE
         WHERE numAnio = @numAnio AND numMes = @numMes AND ideEmpleado = @ideEmpleado AND flgEstado = 1);

    IF @responsable = @txtUsuario
        THROW 50140, 'El trabajador ya esta agregado a su registro del periodo.', 1;

    IF @responsable IS NOT NULL
    BEGIN
        DECLARE @mensaje nvarchar(2048) =
            CONCAT('El trabajador ya fue agregado al periodo por otro responsable de registro (', @responsable, ').');
        THROW 50140, @mensaje, 1;
    END

    DECLARE @idePeriodoEmpleadoResponsable bigint,
            @flgAltaPeriodo bit = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Con dos altas a la vez del mismo trabajador, el bloqueo evita dos filas.
        IF NOT EXISTS (SELECT 1 FROM registro.TMD_PERIODO_EMPLEADO WITH (UPDLOCK, HOLDLOCK)
                       WHERE numAnio = @numAnio AND numMes = @numMes
                         AND ideEmpleado = @ideEmpleado AND flgEstado = 1)
        BEGIN
            -- La columna de usuario de TMD_PERIODO_EMPLEADO admite 30 caracteres.
            INSERT INTO registro.TMD_PERIODO_EMPLEADO
                  (idePeriodo, numAnio, numMes, ideEmpleado, nomEmpleado, flgEstado, txtUsuarioCreacion)
            VALUES (@idePeriodo, @numAnio, @numMes, @ideEmpleado, @nomEmpleado, 1, LEFT(@txtUsuario, 30));

            SET @flgAltaPeriodo = 1;
        END

        INSERT INTO registro.TMD_PERIODO_EMPLEADO_RESPONSABLE
              (idePeriodo, numAnio, numMes, ideEmpleado, nomEmpleado, txtDocumento,
               txtUsuarioResponsable, flgAltaPeriodo, flgEstado, txtUsuarioCreacion)
        VALUES (@idePeriodo, @numAnio, @numMes, @ideEmpleado, @nomEmpleado, @txtDocumento,
               @txtUsuario, @flgAltaPeriodo, 1, @txtUsuario);

        SET @idePeriodoEmpleadoResponsable = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        -- Otro responsable lo agrego entre la comprobacion y el alta: decide el indice unico.
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50140, 'El trabajador ya fue agregado al periodo por otro responsable de registro.', 1;
        THROW;
    END CATCH

    -- Fuera de la transaccion y sin propagar el error: si SPRING no responde,
    -- el trabajador ya quedo agregado y su jefatura se completa en la siguiente alta.
    BEGIN TRY
        EXEC registro.usp_PeriodoEmpleado_CompletarOrganizacion @numAnio = @numAnio, @numMes = @numMes;
    END TRY
    BEGIN CATCH
    END CATCH

    SELECT @idePeriodoEmpleadoResponsable AS idePeriodoEmpleadoResponsable,
           @nomEmpleado AS nomEmpleado;
END
GO

/* -------------------------------------------------------------------------
   4. Quitar un trabajador del registro del responsable

   Solo quien lo agrego lo quita, con el periodo abierto y sin horas del
   trabajador en el periodo (por mes ni por dia). Devuelve el identificador
   de la asignacion dada de baja.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_QuitarTrabajador
    @numAnio     int,
    @numMes      int,
    @ideEmpleado bigint,
    @txtUsuario  varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @flgPeriodo int =
        (SELECT flgEstado FROM registro.TMC_PERIODO
         WHERE numAnio = @numAnio AND numMes = @numMes);

    IF @flgPeriodo IS NULL OR @flgPeriodo <> 1
        THROW 50138, 'El periodo no existe o se encuentra cerrado.', 1;

    DECLARE @idePeriodoEmpleadoResponsable bigint,
            @flgAltaPeriodo bit;

    SELECT @idePeriodoEmpleadoResponsable = idePeriodoEmpleadoResponsable,
           @flgAltaPeriodo = flgAltaPeriodo
    FROM registro.TMD_PERIODO_EMPLEADO_RESPONSABLE
    WHERE numAnio = @numAnio AND numMes = @numMes AND ideEmpleado = @ideEmpleado
      AND txtUsuarioResponsable = @txtUsuario AND flgEstado = 1;

    IF @idePeriodoEmpleadoResponsable IS NULL
        THROW 50141, 'El trabajador no esta agregado a su registro del periodo.', 1;

    IF EXISTS (SELECT 1 FROM registro.TMD_REGISTRO_HORAMES
               WHERE ideEmpleado = @ideEmpleado AND numAnio = @numAnio AND numMes = @numMes
                 AND flgEstado = 1 AND numHoras > 0)
       OR EXISTS (SELECT 1 FROM registro.TMD_REGISTRO_HORADIA
                  WHERE ideEmpleado = @ideEmpleado AND numAnio = @numAnio AND numMes = @numMes
                    AND flgEstado = 1)
        THROW 50142, 'El trabajador ya tiene horas registradas en el periodo: no se puede quitar.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE registro.TMD_PERIODO_EMPLEADO_RESPONSABLE
        SET flgEstado               = 0,
            fecActualizacion        = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE idePeriodoEmpleadoResponsable = @idePeriodoEmpleadoResponsable;

        -- Se deshace el alta que hizo la asignacion, salvo que el trabajador ya
        -- tenga proyectos o registros propios en el periodo.
        IF @flgAltaPeriodo = 1
            UPDATE pe
            SET pe.flgEstado               = 0,
                pe.fecActualizacion        = GETDATE(),
                pe.txtUsuarioActualizacion = LEFT(@txtUsuario, 30)
            FROM registro.TMD_PERIODO_EMPLEADO pe
            WHERE pe.numAnio = @numAnio AND pe.numMes = @numMes
              AND pe.ideEmpleado = @ideEmpleado AND pe.flgEstado = 1
              AND NOT EXISTS (SELECT 1 FROM registro.TMD_PERIODO_PROYECTO pp
                              WHERE pp.numAnio = @numAnio AND pp.numMes = @numMes
                                AND pp.ideEmpleado = @ideEmpleado AND pp.flgEstado = 1)
              AND NOT EXISTS (SELECT 1 FROM registro.TMD_REGISTRO_HORAMES r
                              WHERE r.numAnio = @numAnio AND r.numMes = @numMes
                                AND r.ideEmpleado = @ideEmpleado AND r.flgEstado = 1)
              AND NOT EXISTS (SELECT 1 FROM registro.TMD_REGISTRO_HORADIA d
                              WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                                AND d.ideEmpleado = @ideEmpleado AND d.flgEstado = 1);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @idePeriodoEmpleadoResponsable AS idePeriodoEmpleadoResponsable;
END
GO

/* -------------------------------------------------------------------------
   5. Grilla mensual: filas del responsable
   ------------------------------------------------------------------------- */

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

/* -------------------------------------------------------------------------
   6. Grilla mensual: columnas

   Quien registra (responsable, trabajador) carga en cualquier proyecto
   activo para Costo Labor del periodo, sin agregarlo antes. Se suman los
   proyectos que el trabajador agrego desde el registro por dia y los que ya
   tienen horas, aunque hayan dejado de estar activos: una hora registrada
   nunca queda fuera de la grilla ni de su total. Un mismo codigo sale una
   sola vez, con el nombre del estado de proyectos si lo tiene.

   La jefatura solo valida y no captura: sus columnas siguen siendo los
   proyectos de su equipo, sin cientos de columnas vacias.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarProyectos
    @numAnio               int,
    @numMes                int,
    @ideEmpleadoJefe       bigint = NULL,
    @ideEmpleado           bigint = NULL,
    @txtUsuarioResponsable varchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    WITH visibles AS (
        SELECT pe.ideEmpleado
        FROM registro.TMD_PERIODO_EMPLEADO pe
        WHERE pe.numAnio = @numAnio
          AND pe.numMes  = @numMes
          AND pe.flgEstado = 1
          AND (@ideEmpleadoJefe IS NULL
               OR pe.ideEmpleadoJefe = @ideEmpleadoJefe
               OR pe.ideEmpleado = @ideEmpleadoJefe)
          AND (@ideEmpleado IS NULL OR pe.ideEmpleado = @ideEmpleado)
          AND (@txtUsuarioResponsable IS NULL
               OR EXISTS (SELECT 1 FROM registro.TMD_PERIODO_EMPLEADO_RESPONSABLE a
                          WHERE a.numAnio = pe.numAnio AND a.numMes = pe.numMes
                            AND a.ideEmpleado = pe.ideEmpleado AND a.flgEstado = 1
                            AND a.txtUsuarioResponsable = @txtUsuarioResponsable))
    ),
    columnas AS (
        SELECT e.codProyecto, e.nomProyecto, 1 AS numPrioridad
        FROM proceso.TMD_ESTADO_PROYECTO e
        WHERE e.numAnio = @numAnio
          AND e.numMes  = @numMes
          AND e.flgEstado = 1
          AND e.flgActivoCostoLabor = 1
          AND @ideEmpleadoJefe IS NULL

        UNION ALL

        SELECT pp.codProyecto, pp.nomProyecto, 2
        FROM registro.TMD_PERIODO_PROYECTO pp
        JOIN visibles v ON v.ideEmpleado = pp.ideEmpleado
        WHERE pp.numAnio = @numAnio
          AND pp.numMes  = @numMes
          AND pp.flgEstado = 1

        UNION ALL

        SELECT r.codProyecto, r.nomProyecto, 3
        FROM registro.TMD_REGISTRO_HORAMES r
        JOIN visibles v ON v.ideEmpleado = r.ideEmpleado
        WHERE r.numAnio = @numAnio
          AND r.numMes  = @numMes
          AND r.flgEstado = 1
    ),
    unicos AS (
        SELECT codProyecto, nomProyecto,
               ROW_NUMBER() OVER (PARTITION BY codProyecto ORDER BY numPrioridad) AS numOrden
        FROM columnas
    )
    SELECT codProyecto, nomProyecto
    FROM unicos
    WHERE numOrden = 1
    ORDER BY codProyecto;
END
GO

/* -------------------------------------------------------------------------
   7. Grilla mensual: celdas del responsable
   ------------------------------------------------------------------------- */

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

/* -------------------------------------------------------------------------
   8. Trabajadores con horas por mes ya registradas por un responsable

   Hasta ahora el responsable de registro veia a todos los trabajadores del
   periodo; desde este script ve solo a los que agrego. Las horas que ya
   registro en un periodo abierto quedarian ocultas para todos los
   responsables, asi que el trabajador se asigna a quien las registro.

   Cuenta como quien registro el usuario que creo o actualizo cada fila de
   horas activa del trabajador en el periodo, si hoy tiene activo el perfil
   Responsable de registro. La columna de usuario de las horas admite 30
   caracteres y el alta desde el registro por dia lo recorta: se compara
   tambien contra los primeros 30 del usuario. Se guarda el usuario completo,
   que es el que llega en el token.

   Con dos o mas responsables no se asigna a ninguno: se listan (sin nombres)
   para resolverlos a mano. Los periodos cerrados no se tocan. No se repite:
   solo considera trabajadores sin asignacion activa en el periodo.
   ------------------------------------------------------------------------- */

DECLARE @responsables TABLE (
    numAnio               int          NOT NULL,
    numMes                int          NOT NULL,
    ideEmpleado           bigint       NOT NULL,
    txtUsuarioResponsable varchar(100) NOT NULL,
    PRIMARY KEY (numAnio, numMes, ideEmpleado, txtUsuarioResponsable)
);

INSERT INTO @responsables (numAnio, numMes, ideEmpleado, txtUsuarioResponsable)
SELECT DISTINCT r.numAnio, r.numMes, r.ideEmpleado, pu.txtUsuario
FROM registro.TMD_REGISTRO_HORAMES r
JOIN registro.TMC_PERIODO p
  ON p.numAnio = r.numAnio AND p.numMes = r.numMes AND p.flgEstado = 1
CROSS APPLY (VALUES (r.txtUsuarioCreacion), (r.txtUsuarioActualizacion)) AS u(txtUsuario)
JOIN seguridad.TMD_PERFIL_USUARIO pu
  ON pu.flgEstado = 1
 AND (pu.txtUsuario = u.txtUsuario
      OR (LEN(u.txtUsuario) = 30 AND LEFT(pu.txtUsuario, 30) = u.txtUsuario))
JOIN seguridad.TMC_PERFIL pf
  ON pf.idePerfil = pu.idePerfil AND pf.flgEstado = 1 AND pf.codPerfil = 'RESPONSABLE_REGISTRO'
WHERE r.flgEstado = 1
  AND u.txtUsuario IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM registro.TMD_PERIODO_EMPLEADO_RESPONSABLE a
                  WHERE a.numAnio = r.numAnio AND a.numMes = r.numMes
                    AND a.ideEmpleado = r.ideEmpleado AND a.flgEstado = 1);

-- flgAltaPeriodo = 0: el trabajador ya estaba en el periodo; quitarlo no lo saca.
INSERT INTO registro.TMD_PERIODO_EMPLEADO_RESPONSABLE
      (idePeriodo, numAnio, numMes, ideEmpleado, nomEmpleado, txtDocumento,
       txtUsuarioResponsable, flgAltaPeriodo, flgEstado, txtUsuarioCreacion)
SELECT p.idePeriodo, u.numAnio, u.numMes, u.ideEmpleado,
       COALESCE(pe.nomEmpleado, h.nomEmpleado, CAST(u.ideEmpleado AS varchar(20))),
       NULL, u.txtUsuarioResponsable, 0, 1, 'SCRIPT_52'
FROM (SELECT numAnio, numMes, ideEmpleado, MAX(txtUsuarioResponsable) AS txtUsuarioResponsable
      FROM @responsables
      GROUP BY numAnio, numMes, ideEmpleado
      HAVING COUNT(*) = 1) u
JOIN registro.TMC_PERIODO p ON p.numAnio = u.numAnio AND p.numMes = u.numMes
OUTER APPLY (SELECT TOP (1) pe.nomEmpleado FROM registro.TMD_PERIODO_EMPLEADO pe
             WHERE pe.numAnio = u.numAnio AND pe.numMes = u.numMes
               AND pe.ideEmpleado = u.ideEmpleado AND pe.flgEstado = 1) pe
OUTER APPLY (SELECT MAX(r.nomEmpleado) AS nomEmpleado FROM registro.TMD_REGISTRO_HORAMES r
             WHERE r.numAnio = u.numAnio AND r.numMes = u.numMes
               AND r.ideEmpleado = u.ideEmpleado AND r.flgEstado = 1) h;

DECLARE @numAsignados int = @@ROWCOUNT;
PRINT CONCAT('Trabajadores asignados al responsable que registro sus horas: ', @numAsignados);

IF EXISTS (SELECT 1 FROM @responsables GROUP BY numAnio, numMes, ideEmpleado HAVING COUNT(*) > 1)
BEGIN
    PRINT 'Trabajadores con horas de dos o mas responsables, sin asignar: agreguelos a mano desde la pantalla.';
    SELECT numAnio, numMes, ideEmpleado, COUNT(*) AS numResponsables
    FROM @responsables
    GROUP BY numAnio, numMes, ideEmpleado
    HAVING COUNT(*) > 1
    ORDER BY numAnio, numMes, ideEmpleado;
END
ELSE
    PRINT 'No hay trabajadores con horas de dos o mas responsables.';
GO

/* -------------------------------------------------------------------------
   9. Personal de SPRING de la asignacion de areas

   Ultima version: script 47. La asignacion de areas usa la consulta de
   personal del registro de horas por mes, que comparaba mes y anio de cese
   por separado y descartaba a quien no tiene fecha de cese: dejaba fuera al
   personal en actividad. Solo cambia el filtro, a la misma regla de la
   seccion 2; firma, columnas y orden no cambian.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_PersonalSpring_ListarPeriodo
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT CAST(NULL AS bigint) AS idePersona, CAST(NULL AS varchar(150)) AS txtNombreCompleto,
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
        WHERE em.Empleado IS NOT NULL
          AND (em.FechaCese IS NULL
               OR @anio_actual * 100 + @mes_actual <= YEAR(em.FechaCese) * 100 + MONTH(em.FechaCese))
        ORDER BY txtNombreCompleto;',
        N'@mes_actual int, @anio_actual int', @mes_actual = @numMes, @anio_actual = @numAnio;
END
GO
