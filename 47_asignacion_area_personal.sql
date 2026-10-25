/* =========================================================================
   47 - Asignacion de personal a areas por periodo

   Hay casos en que el personal debe figurar en otra area para el calculo
   del DETALLE_GASTO_PERSONAL y el RESUMEN_GASTO_PERSONAL (encargaturas,
   licencias por maternidad u otros) y SPRING no lo registra. El Contador
   asigna por periodo a una persona en un area de SPRING (HR_Division), con
   un motivo obligatorio. "Replicar del periodo anterior" copia las
   asignaciones del ultimo periodo que las tenga.

   El listado de personal es la consulta de referencia del registro de horas
   por mes (registro.usp_PersonalSpring_ListarPeriodo), que tambien puede
   usar esa opcion.

   La opcion exige su marca de registros completados (script 43).

   Errores nuevos:
     50120  el periodo esta cerrado
     50121  la persona no existe en SPRING
     50122  el area no existe en SPRING
     50123  falta el motivo
     50124  la persona ya tiene una asignacion en el periodo
     50125  la asignacion no existe
     50126  no hay un periodo anterior con asignaciones que replicar

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Tabla
   ------------------------------------------------------------------------- */

IF OBJECT_ID('proceso.TMD_ASIGNACION_AREA') IS NULL
BEGIN
    -- Nombres copiados de SPRING: el periodo cerrado sigue mostrando los de entonces.
    CREATE TABLE proceso.TMD_ASIGNACION_AREA(
        ideAsignacionArea bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        idePersona bigint NOT NULL,
        nomPersona varchar(150) NOT NULL,
        txtDocumento varchar(20) NULL,
        codArea varchar(20) NOT NULL,
        nomArea varchar(200) NOT NULL,
        txtMotivo varchar(300) NOT NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMD_ASIGNACION_AREA_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_ASIGNACION_AREA_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMD_ASIGNACION_AREA PRIMARY KEY CLUSTERED (ideAsignacionArea ASC)
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_ASIGNACION_AREA_PERIODO
        ON proceso.TMD_ASIGNACION_AREA (numAnio, numMes, idePersona) WHERE flgEstado = 1;
END
GO

/* -------------------------------------------------------------------------
   2. Personal de SPRING del periodo

   Consulta de referencia del registro de horas por mes: personal cuyo mes de
   cese no es anterior al periodo. Vacio si BD_SPRING no esta disponible.
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
        WHERE DATEPART(mm, em.FechaCese) >= @mes_actual
          AND DATEPART(yyyy, em.FechaCese) >= @anio_actual
        ORDER BY txtNombreCompleto;',
        N'@mes_actual int, @anio_actual int', @mes_actual = @numMes, @anio_actual = @numAnio;
END
GO

/* -------------------------------------------------------------------------
   3. Areas de SPRING
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_AreaSpring_Listar
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT CAST(NULL AS varchar(20)) AS codArea, CAST(NULL AS varchar(200)) AS nomArea WHERE 1 = 0;
        RETURN;
    END

    EXEC sp_executesql N'
        SELECT CAST(TRIM(CAST(d.Division AS varchar(20))) AS varchar(20)) AS codArea,
               CAST(TRIM(d.DescripcionLarga) AS varchar(200)) AS nomArea
        FROM BD_SPRING.dbo.HR_Division d
        WHERE d.DescripcionLarga IS NOT NULL
        ORDER BY nomArea;';
END
GO

/* -------------------------------------------------------------------------
   4. Listado del periodo
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

    SELECT a.ideAsignacionArea, a.idePersona, a.nomPersona, a.txtDocumento, a.codArea, a.nomArea, a.txtMotivo
    FROM proceso.TMD_ASIGNACION_AREA a
    WHERE a.numAnio = @numAnio AND a.numMes = @numMes AND a.flgEstado = 1
    ORDER BY a.nomPersona;
END
GO

/* -------------------------------------------------------------------------
   5. Registrar o editar

   Con @ideAsignacionArea nulo es un alta en el periodo indicado; si no, se
   edita (area y motivo) y el periodo y la persona son los del registro.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_AsignacionArea_Guardar
    @ideAsignacionArea bigint = NULL,
    @numAnio           int,
    @numMes            int,
    @idePersona        bigint,
    @codArea           varchar(20),
    @txtMotivo         varchar(300),
    @txtUsuario        varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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

    IF EXISTS (SELECT 1 FROM proceso.TMD_ASIGNACION_AREA
               WHERE numAnio = @numAnio AND numMes = @numMes AND idePersona = @idePersona AND flgEstado = 1
                 AND ideAsignacionArea <> ISNULL(@ideAsignacionArea, 0))
        THROW 50124, 'La persona ya tiene una asignacion de area en el periodo.', 1;

    IF @ideAsignacionArea IS NULL
    BEGIN
        INSERT INTO proceso.TMD_ASIGNACION_AREA
               (numAnio, numMes, idePersona, nomPersona, txtDocumento, codArea, nomArea, txtMotivo,
                flgEstado, txtUsuarioCreacion)
        VALUES (@numAnio, @numMes, @idePersona, @nomPersona, @txtDocumento, TRIM(@codArea), @nomArea,
                TRIM(@txtMotivo), 1, @txtUsuario);
        SET @ideAsignacionArea = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE proceso.TMD_ASIGNACION_AREA
        SET codArea = TRIM(@codArea),
            nomArea = @nomArea,
            txtMotivo = TRIM(@txtMotivo),
            fecActualizacion = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE ideAsignacionArea = @ideAsignacionArea;

    SELECT @ideAsignacionArea AS ideAsignacionArea;
END
GO

/* -------------------------------------------------------------------------
   6. Eliminar (baja logica)
   ------------------------------------------------------------------------- */

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
END
GO

/* -------------------------------------------------------------------------
   7. Replicar del periodo anterior

   Copia las asignaciones del ultimo periodo anterior que las tenga, salvo
   las de personas que ya tienen asignacion en el periodo. Devuelve de donde
   copio y cuantas copio.
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
            flgEstado, txtUsuarioCreacion)
    SELECT @numAnio, @numMes, o.idePersona, o.nomPersona, o.txtDocumento, o.codArea, o.nomArea, o.txtMotivo,
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
   8. Opcion de menu del Contador y marca de registros completados

   Igual que los scripts 33 y 36: idempotente y sin filtrar por flgEstado.
   ------------------------------------------------------------------------- */

SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'ASIGNACION_AREA_PERSONAL', 'Asignación de personal a áreas', '/costo-labor/asignacion-areas',
       'bi bi-person-lines-fill', p.ideOpcion, 10, 1, @usuario
FROM seguridad.TG_OPCION p
WHERE p.codOpcion = 'COSTO_LABOR'
  AND NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'ASIGNACION_AREA_PERSONAL');

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('CONTADOR', 'ASIGNACION_AREA_PERSONAL')) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);

INSERT INTO proceso.TMC_REGISTRO_PREVIO (codOpcion, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'ASIGNACION_AREA_PERSONAL', 50, 1, @usuario
WHERE NOT EXISTS (SELECT 1 FROM proceso.TMC_REGISTRO_PREVIO
                  WHERE codOpcion = 'ASIGNACION_AREA_PERSONAL' AND flgEstado = 1);
GO
