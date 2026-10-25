/* =========================================================================
   45 - Registro de rentabilidad por proyecto

   Tesoreria informa cada mes, por memorando, la rentabilidad de los fondos
   por proyecto y la parte que corresponde al costo labor. El perfil nuevo
   Tesoreria la registra por periodo:

     - Proyecto a proyecto, o cargando la plantilla Excel. La carga es todo o
       nada: si una fila tiene error no se registra ninguna y se informan
       todas las filas con error. Una carga correcta reemplaza lo registrado
       en el periodo.
     - El PDF del memorando y su nombre ("MEMORANDO 085-2026-GAF/TES"), que
       es el texto que sale junto al total en la hoja RESUMEN_COSTO_LABOR.

   El proyecto se valida contra BD_SPRING (afemst), que es de donde salen
   los proyectos del sistema.

   La opcion exige su marca de registros completados (script 43), que la
   da Tesoreria.

   Errores nuevos:
     50114  el periodo esta cerrado
     50115  el proyecto no existe en SPRING (o SPRING no esta disponible)
     50116  el proyecto ya esta registrado en el periodo
     50117  montos no validos
     50118  el registro no existe
     50119  documento no valido

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Tablas y tipo de la carga masiva
   ------------------------------------------------------------------------- */

IF OBJECT_ID('proceso.TMD_RENTABILIDAD_PROYECTO') IS NULL
BEGIN
    CREATE TABLE proceso.TMD_RENTABILIDAD_PROYECTO(
        ideRentabilidadProyecto bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        codProyecto varchar(30) NOT NULL,
        -- Copia del nombre de SPRING: el periodo cerrado sigue mostrando el de entonces.
        nomProyecto varchar(200) NOT NULL,
        numMontoTotal decimal(14,2) NOT NULL,
        numMontoRentabilidad decimal(14,2) NOT NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMD_RENTABILIDAD_PROYECTO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_RENTABILIDAD_PROYECTO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMD_RENTABILIDAD_PROYECTO PRIMARY KEY CLUSTERED (ideRentabilidadProyecto ASC)
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_RENTABILIDAD_PROYECTO_PERIODO
        ON proceso.TMD_RENTABILIDAD_PROYECTO (numAnio, numMes, codProyecto) WHERE flgEstado = 1;
END
GO

IF OBJECT_ID('proceso.TMD_RENTABILIDAD_DOCUMENTO') IS NULL
BEGIN
    CREATE TABLE proceso.TMD_RENTABILIDAD_DOCUMENTO(
        ideRentabilidadDocumento bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        txtDocumento varchar(150) NOT NULL,
        nomArchivo varchar(255) NOT NULL,
        binArchivo varbinary(max) NOT NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMD_RENTABILIDAD_DOCUMENTO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_RENTABILIDAD_DOCUMENTO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMD_RENTABILIDAD_DOCUMENTO PRIMARY KEY CLUSTERED (ideRentabilidadDocumento ASC)
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_RENTABILIDAD_DOCUMENTO_PERIODO
        ON proceso.TMD_RENTABILIDAD_DOCUMENTO (numAnio, numMes) WHERE flgEstado = 1;
END
GO

IF TYPE_ID('proceso.TYPE_RENTABILIDAD_FILA') IS NULL
    CREATE TYPE proceso.TYPE_RENTABILIDAD_FILA AS TABLE (
        numFila int NOT NULL PRIMARY KEY,
        codProyecto varchar(30) NOT NULL,
        numMontoTotal decimal(14,2) NOT NULL,
        numMontoRentabilidad decimal(14,2) NOT NULL
    );
GO

/* -------------------------------------------------------------------------
   2. Proyectos de SPRING

   Consulta de referencia del script 36. Vacio si BD_SPRING no esta disponible.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ProyectoSpring_Listar
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT CAST(NULL AS varchar(30)) AS codProyecto, CAST(NULL AS varchar(200)) AS nomProyecto WHERE 1 = 0;
        RETURN;
    END

    EXEC sp_executesql N'
        SELECT codProyecto, nomProyecto
        FROM (
            SELECT CAST(TRIM(afe) AS varchar(30)) AS codProyecto,
                   CAST(TRIM(englishname) AS varchar(200)) AS nomProyecto,
                   ROW_NUMBER() OVER (PARTITION BY TRIM(afe) ORDER BY englishname) AS numOrden
            FROM BD_SPRING.dbo.afemst
            WHERE afe IS NOT NULL AND englishname IS NOT NULL
        ) a
        WHERE numOrden = 1;';
END
GO

/* -------------------------------------------------------------------------
   3. Listado del periodo

   Tres conjuntos: si el periodo esta cerrado, el documento (vacio si no hay)
   y los proyectos.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_Rentabilidad_Listar
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
                     THEN 1 ELSE 0 END AS bit) AS flgCerrado;

    SELECT d.txtDocumento, d.nomArchivo, DATALENGTH(d.binArchivo) AS numTamanio,
           ISNULL(d.txtUsuarioActualizacion, d.txtUsuarioCreacion) AS txtUsuario,
           ISNULL(d.fecActualizacion, d.fecCreacion) AS fecDocumento
    FROM proceso.TMD_RENTABILIDAD_DOCUMENTO d
    WHERE d.numAnio = @numAnio AND d.numMes = @numMes AND d.flgEstado = 1;

    SELECT r.ideRentabilidadProyecto, r.codProyecto, r.nomProyecto,
           r.numMontoTotal, r.numMontoRentabilidad
    FROM proceso.TMD_RENTABILIDAD_PROYECTO r
    WHERE r.numAnio = @numAnio AND r.numMes = @numMes AND r.flgEstado = 1
    ORDER BY r.nomProyecto, r.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   4. Registrar o editar un proyecto

   Con @ideRentabilidadProyecto nulo es un alta en el periodo indicado; si
   no, se edita y el periodo es el del registro.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_Rentabilidad_Guardar
    @ideRentabilidadProyecto bigint = NULL,
    @numAnio                 int,
    @numMes                  int,
    @codProyecto             varchar(30),
    @numMontoTotal           decimal(14,2),
    @numMontoRentabilidad    decimal(14,2),
    @txtUsuario              varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @ideRentabilidadProyecto IS NOT NULL
    BEGIN
        SELECT @numAnio = numAnio, @numMes = numMes
        FROM proceso.TMD_RENTABILIDAD_PROYECTO
        WHERE ideRentabilidadProyecto = @ideRentabilidadProyecto AND flgEstado = 1;

        IF @@ROWCOUNT = 0
            THROW 50118, 'El registro de rentabilidad no existe.', 1;
    END

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50114, 'El periodo esta cerrado: su rentabilidad no se puede modificar.', 1;

    IF @numMontoTotal IS NULL OR @numMontoRentabilidad IS NULL
       OR @numMontoTotal < 0 OR @numMontoRentabilidad < 0 OR @numMontoRentabilidad > @numMontoTotal
        THROW 50117, 'Ingrese el monto total y el de rentabilidad, mayores o iguales a cero; la rentabilidad no puede superar al total.', 1;

    CREATE TABLE #spring (codProyecto varchar(30) NOT NULL PRIMARY KEY, nomProyecto varchar(200) NOT NULL);
    INSERT INTO #spring (codProyecto, nomProyecto) EXEC proceso.usp_ProyectoSpring_Listar;

    DECLARE @nomProyecto varchar(200) = (SELECT nomProyecto FROM #spring WHERE codProyecto = TRIM(@codProyecto));
    IF @nomProyecto IS NULL
        THROW 50115, 'El codigo de proyecto no existe en SPRING.', 1;

    IF EXISTS (SELECT 1 FROM proceso.TMD_RENTABILIDAD_PROYECTO
               WHERE numAnio = @numAnio AND numMes = @numMes AND codProyecto = TRIM(@codProyecto)
                 AND flgEstado = 1
                 AND ideRentabilidadProyecto <> ISNULL(@ideRentabilidadProyecto, 0))
        THROW 50116, 'El proyecto ya tiene rentabilidad registrada en el periodo.', 1;

    IF @ideRentabilidadProyecto IS NULL
    BEGIN
        INSERT INTO proceso.TMD_RENTABILIDAD_PROYECTO
               (numAnio, numMes, codProyecto, nomProyecto, numMontoTotal, numMontoRentabilidad,
                flgEstado, txtUsuarioCreacion)
        VALUES (@numAnio, @numMes, TRIM(@codProyecto), @nomProyecto, @numMontoTotal, @numMontoRentabilidad,
                1, @txtUsuario);
        SET @ideRentabilidadProyecto = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE proceso.TMD_RENTABILIDAD_PROYECTO
        SET codProyecto = TRIM(@codProyecto),
            nomProyecto = @nomProyecto,
            numMontoTotal = @numMontoTotal,
            numMontoRentabilidad = @numMontoRentabilidad,
            fecActualizacion = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE ideRentabilidadProyecto = @ideRentabilidadProyecto;

    SELECT @ideRentabilidadProyecto AS ideRentabilidadProyecto;
END
GO

/* -------------------------------------------------------------------------
   5. Eliminar un proyecto (baja logica)
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_Rentabilidad_Eliminar
    @ideRentabilidadProyecto bigint,
    @txtUsuario              varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @numAnio int, @numMes int;
    SELECT @numAnio = numAnio, @numMes = numMes
    FROM proceso.TMD_RENTABILIDAD_PROYECTO
    WHERE ideRentabilidadProyecto = @ideRentabilidadProyecto AND flgEstado = 1;

    IF @numAnio IS NULL
        THROW 50118, 'El registro de rentabilidad no existe.', 1;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50114, 'El periodo esta cerrado: su rentabilidad no se puede modificar.', 1;

    UPDATE proceso.TMD_RENTABILIDAD_PROYECTO
    SET flgEstado = 0,
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE ideRentabilidadProyecto = @ideRentabilidadProyecto;
END
GO

/* -------------------------------------------------------------------------
   6. Carga de la plantilla: todo o nada

   El formato de cada fila (codigo y montos presentes y validos) lo revisa el
   backend al leer el Excel. Aqui se revisa lo que depende de la base: que el
   proyecto exista en SPRING y que no se repita en el archivo. Devuelve las
   filas con error; si no hay ninguna, reemplaza lo registrado en el periodo.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_Rentabilidad_Cargar
    @numAnio    int,
    @numMes     int,
    @filas      proceso.TYPE_RENTABILIDAD_FILA READONLY,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50114, 'El periodo esta cerrado: su rentabilidad no se puede modificar.', 1;

    CREATE TABLE #spring (codProyecto varchar(30) NOT NULL PRIMARY KEY, nomProyecto varchar(200) NOT NULL);
    INSERT INTO #spring (codProyecto, nomProyecto) EXEC proceso.usp_ProyectoSpring_Listar;

    SELECT e.numFila, e.txtError
    INTO #errores
    FROM (
        SELECT f.numFila, CAST('El codigo de proyecto ' + TRIM(f.codProyecto) + ' no existe en SPRING.' AS varchar(300)) AS txtError
        FROM @filas f
        WHERE NOT EXISTS (SELECT 1 FROM #spring s WHERE s.codProyecto = TRIM(f.codProyecto))
        UNION ALL
        SELECT f.numFila, CAST('El proyecto ' + TRIM(f.codProyecto) + ' esta repetido en el archivo.' AS varchar(300))
        FROM @filas f
        WHERE EXISTS (SELECT 1 FROM @filas o
                      WHERE TRIM(o.codProyecto) = TRIM(f.codProyecto) AND o.numFila < f.numFila)
    ) e;

    IF NOT EXISTS (SELECT 1 FROM #errores)
    BEGIN
        BEGIN TRANSACTION;

        UPDATE proceso.TMD_RENTABILIDAD_PROYECTO
        SET flgEstado = 0,
            fecActualizacion = GETDATE(),
            txtUsuarioActualizacion = @txtUsuario
        WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1;

        INSERT INTO proceso.TMD_RENTABILIDAD_PROYECTO
               (numAnio, numMes, codProyecto, nomProyecto, numMontoTotal, numMontoRentabilidad,
                flgEstado, txtUsuarioCreacion)
        SELECT @numAnio, @numMes, s.codProyecto, s.nomProyecto, f.numMontoTotal, f.numMontoRentabilidad,
               1, @txtUsuario
        FROM @filas f
        INNER JOIN #spring s ON s.codProyecto = TRIM(f.codProyecto);

        COMMIT TRANSACTION;
    END

    SELECT numFila, txtError FROM #errores ORDER BY numFila, txtError;
END
GO

/* -------------------------------------------------------------------------
   7. Documento de sustento: uno por periodo, reemplazable
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_RentabilidadDocumento_Guardar
    @numAnio      int,
    @numMes       int,
    @txtDocumento varchar(150),
    @nomArchivo   varchar(255),
    @binArchivo   varbinary(max),
    @txtUsuario   varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50114, 'El periodo esta cerrado: su rentabilidad no se puede modificar.', 1;

    IF NULLIF(TRIM(@txtDocumento), '') IS NULL OR NULLIF(TRIM(@nomArchivo), '') IS NULL
       OR @binArchivo IS NULL OR DATALENGTH(@binArchivo) = 0
        THROW 50119, 'Indique el nombre del documento y adjunte el PDF.', 1;

    BEGIN TRANSACTION;

    UPDATE proceso.TMD_RENTABILIDAD_DOCUMENTO WITH (UPDLOCK, HOLDLOCK)
    SET txtDocumento = TRIM(@txtDocumento),
        nomArchivo = TRIM(@nomArchivo),
        binArchivo = @binArchivo,
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 1;

    IF @@ROWCOUNT = 0
        INSERT INTO proceso.TMD_RENTABILIDAD_DOCUMENTO
               (numAnio, numMes, txtDocumento, nomArchivo, binArchivo, flgEstado, txtUsuarioCreacion)
        VALUES (@numAnio, @numMes, TRIM(@txtDocumento), TRIM(@nomArchivo), @binArchivo, 1, @txtUsuario);

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE proceso.usp_RentabilidadDocumento_Obtener
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT d.nomArchivo, d.binArchivo
    FROM proceso.TMD_RENTABILIDAD_DOCUMENTO d
    WHERE d.numAnio = @numAnio AND d.numMes = @numMes AND d.flgEstado = 1;
END
GO

/* -------------------------------------------------------------------------
   8. Perfil Tesoreria, opcion de menu y marca de registros completados

   Igual que los scripts 33 y 36: idempotente y sin filtrar por flgEstado,
   para no devolver la opcion a un perfil al que el administrador se la quito.
   ------------------------------------------------------------------------- */

SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMC_PERFIL (codPerfil, nomPerfil, txtDescripcion, flgEstado, txtUsuarioCreacion)
SELECT 'TESORERIA', 'Tesorería', 'Registra la rentabilidad por proyecto para el costo labor', 1, @usuario
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMC_PERFIL WHERE codPerfil = 'TESORERIA');

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'RENTABILIDAD_PROYECTO', 'Registro de rentabilidad por proyecto', '/costo-labor/rentabilidad-proyectos',
       'bi bi-cash-coin', p.ideOpcion, 9, 1, @usuario
FROM seguridad.TG_OPCION p
WHERE p.codOpcion = 'COSTO_LABOR'
  AND NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'RENTABILIDAD_PROYECTO');

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('TESORERIA', 'COSTO_LABOR'), ('TESORERIA', 'RENTABILIDAD_PROYECTO')) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);

INSERT INTO proceso.TMC_REGISTRO_PREVIO (codOpcion, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'RENTABILIDAD_PROYECTO', 60, 1, @usuario
WHERE NOT EXISTS (SELECT 1 FROM proceso.TMC_REGISTRO_PREVIO
                  WHERE codOpcion = 'RENTABILIDAD_PROYECTO' AND flgEstado = 1);
GO
