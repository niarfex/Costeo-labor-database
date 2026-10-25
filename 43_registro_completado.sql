/* =========================================================================
   43 - Registros completados para el periodo

   Antes de procesar un periodo, el Contador debe indicar en cada opcion de
   Costo Labor que ya reviso sus registros ("Registros completados para el
   periodo"). La marca se da aunque la opcion quede vacia: un periodo puede no
   tener gasto no recuperable, por ejemplo.

   Las opciones que exigen la marca estan en proceso.TMC_REGISTRO_PREVIO, por
   su codOpcion del menu (seguridad.TG_OPCION), de donde salen el nombre y la
   ruta. Una opcion nueva de Costo Labor se suma insertando su fila en su
   propio script, igual que aqui.

   La marca se guarda por anio y mes, como el estado de proyectos: el periodo
   puede no existir todavia. "Replicar del periodo anterior" no la copia.

   La validacion antes de procesar la hace el backend con el listado de este
   script, para no modificar proceso.usp_Periodo_Procesar.

   Errores nuevos:
     50110  el periodo esta cerrado
     50111  la opcion no exige la marca de registros completados
     50112  falta indicar si los registros estan completados

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Tablas
   ------------------------------------------------------------------------- */

IF OBJECT_ID('proceso.TMC_REGISTRO_PREVIO') IS NULL
BEGIN
    CREATE TABLE proceso.TMC_REGISTRO_PREVIO(
        ideRegistroPrevio int IDENTITY(1,1) NOT NULL,
        codOpcion varchar(50) NOT NULL,
        numOrden int NOT NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMC_REGISTRO_PREVIO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMC_REGISTRO_PREVIO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMC_REGISTRO_PREVIO PRIMARY KEY CLUSTERED (ideRegistroPrevio ASC)
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMC_REGISTRO_PREVIO_OPCION
        ON proceso.TMC_REGISTRO_PREVIO (codOpcion) WHERE flgEstado = 1;
END
GO

IF OBJECT_ID('proceso.TMD_REGISTRO_COMPLETADO') IS NULL
BEGIN
    CREATE TABLE proceso.TMD_REGISTRO_COMPLETADO(
        ideRegistroCompletado bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        codOpcion varchar(50) NOT NULL,
        flgCompletado bit NOT NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMD_REGISTRO_COMPLETADO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_REGISTRO_COMPLETADO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMD_REGISTRO_COMPLETADO PRIMARY KEY CLUSTERED (ideRegistroCompletado ASC)
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_REGISTRO_COMPLETADO_PERIODO
        ON proceso.TMD_REGISTRO_COMPLETADO (numAnio, numMes, codOpcion) WHERE flgEstado = 1;
END
GO

/* -------------------------------------------------------------------------
   2. Opciones que exigen la marca
   ------------------------------------------------------------------------- */

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO proceso.TMC_REGISTRO_PREVIO (codOpcion, numOrden, flgEstado, txtUsuarioCreacion)
SELECT n.codOpcion, n.numOrden, 1, @usuario
FROM (VALUES
    ('GASTO_NO_RECUPERABLE', 10),
    ('ESTADO_PROYECTOS', 20),
    ('CATEGORIZACION_PROYECTOS', 30),
    ('TIPO_GASTO_PERSONAL', 40)
) n (codOpcion, numOrden)
WHERE NOT EXISTS (SELECT 1 FROM proceso.TMC_REGISTRO_PREVIO r
                  WHERE r.codOpcion = n.codOpcion AND r.flgEstado = 1);
GO

/* -------------------------------------------------------------------------
   3. Listado del periodo

   Primero si el periodo esta cerrado y luego cada opcion con su marca, en
   dos conjuntos de resultados. Una opcion sin marca sale con flgCompletado 0.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_RegistroCompletado_Listar
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
                     THEN 1 ELSE 0 END AS bit) AS flgCerrado;

    SELECT r.codOpcion, o.nomOpcion, o.txtRuta,
           CAST(ISNULL(c.flgCompletado, 0) AS bit) AS flgCompletado,
           ISNULL(c.txtUsuarioActualizacion, c.txtUsuarioCreacion) AS txtUsuario,
           ISNULL(c.fecActualizacion, c.fecCreacion) AS fecMarca
    FROM proceso.TMC_REGISTRO_PREVIO r
    INNER JOIN seguridad.TG_OPCION o
            ON o.codOpcion = r.codOpcion AND o.flgEstado = 1
    LEFT JOIN proceso.TMD_REGISTRO_COMPLETADO c
           ON c.codOpcion = r.codOpcion AND c.numAnio = @numAnio AND c.numMes = @numMes
          AND c.flgEstado = 1
    WHERE r.flgEstado = 1
    ORDER BY r.numOrden, r.codOpcion;
END
GO

/* -------------------------------------------------------------------------
   4. Marcar o desmarcar

   Se guarda en cada cambio del check. Si la opcion aun no tiene fila en el
   periodo se crea; si ya la tiene se actualiza.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_RegistroCompletado_Marcar
    @numAnio       int,
    @numMes        int,
    @codOpcion     varchar(50),
    @flgCompletado bit,
    @txtUsuario    varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50110, 'El periodo esta cerrado: sus registros completados no se pueden modificar.', 1;

    IF NOT EXISTS (SELECT 1 FROM proceso.TMC_REGISTRO_PREVIO
                   WHERE codOpcion = @codOpcion AND flgEstado = 1)
        THROW 50111, 'La opcion indicada no requiere la marca de registros completados.', 1;

    IF @flgCompletado IS NULL
        THROW 50112, 'Indique si los registros del periodo estan completados.', 1;

    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    -- UPDLOCK + HOLDLOCK: dos clics simultaneos no insertan la fila dos veces.
    UPDATE proceso.TMD_REGISTRO_COMPLETADO WITH (UPDLOCK, HOLDLOCK)
    SET flgCompletado = @flgCompletado,
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE numAnio = @numAnio AND numMes = @numMes AND codOpcion = @codOpcion AND flgEstado = 1;

    IF @@ROWCOUNT = 0
        INSERT INTO proceso.TMD_REGISTRO_COMPLETADO
               (numAnio, numMes, codOpcion, flgCompletado, flgEstado, txtUsuarioCreacion)
        VALUES (@numAnio, @numMes, @codOpcion, @flgCompletado, 1, @txtUsuario);

    COMMIT TRANSACTION;
END
GO
