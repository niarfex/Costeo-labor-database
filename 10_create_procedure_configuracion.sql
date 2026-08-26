/* ============================================================================
   HU-002 - Configuraciones generales.

   Opera sobre general.TG_CONFIGURACION, que ya crea 01_create_table.sql.
   No se crean ni alteran tablas aqui.

   La tabla tiene dos columnas de valor y cada parametro usa una sola:
     numParametro (int)          enteros, como TIEMPO_INACTIVIDAD.
     txtParametro (varchar 100)  porcentajes con 2 decimales de la distribucion
                                 del gasto, que no caben en un int.

   Errores de negocio, mismos codigos que 05_create_procedure.sql:
     50003 configuracion no encontrada
   ============================================================================ */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================================
   Semilla de los parametros de la HU-002

   Se inserta solo lo que falta, para poder reejecutar el script sin duplicar ni
   pisar valores que el administrador ya haya cambiado desde la aplicacion.
   ============================================================================ */
DECLARE @configuraciones TABLE (
    codigo      varchar(30),
    numValor    int,
    txtValor    varchar(100),
    minimo      int,
    maximo      int,
    descripcion varchar(200)
);

INSERT INTO @configuraciones (codigo, numValor, txtValor, minimo, maximo, descripcion) VALUES
    ('TIEMPO_INACTIVIDAD',           30,   NULL,    0, 0,  'Tiempo de inactividad en minutos'),
    ('MAX_CANT_INTENTO_FALLIDO',     5,    NULL,    0, 25, 'Cantidad de intentos fallidos antes del bloqueo'),
    ('TIEMPO_BLOQUEO_INICIO_SESION', 15,   NULL,    0, 30, 'Tiempo de bloqueo de inicio de sesion en minutos'),
    -- Distribucion del gasto de personal. Los valores son los del prototipo:
    -- GIP + GO = 100.00 y los cuatro departamentos suman GO.
    ('DIST_GIP',                     NULL, '0.50',  NULL, NULL, 'Linea Core 1 (GIP)'),
    ('DIST_GO',                      NULL, '99.50', NULL, NULL, 'Linea Core 2 (GO)'),
    ('DIST_GO_ING_PROYECTOS',        NULL, '20.00', NULL, NULL, 'Departamento de Ingenieria de Proyectos'),
    ('DIST_GO_GESTION_OBRAS',        NULL, '30.00', NULL, NULL, 'Departamento de Gestion de Obras'),
    ('DIST_GO_POST_CIERRE',          NULL, '47.00', NULL, NULL, 'Departamento de Post Cierre y Mantenimiento'),
    ('DIST_GO_REL_COMUNITARIAS',     NULL, '2.50',  NULL, NULL, 'Relaciones Comunitarias');

INSERT INTO general.TG_CONFIGURACION
      (txtCodigoConfiguracion, numParametro, txtParametro, numMinimo, numMaximo,
       txtDescripcion, flgEstado, fecCreacion, txtUsuarioCreacion)
SELECT c.codigo, c.numValor, c.txtValor, c.minimo, c.maximo,
       c.descripcion, 1, GETDATE(), 'SYSTEM_COSTOLABOR'
FROM @configuraciones c
WHERE NOT EXISTS (
    SELECT 1 FROM general.TG_CONFIGURACION t
    WHERE t.txtCodigoConfiguracion = c.codigo
);
GO

/* ---------------------------------------------------------------------------
   Listado para precargar la vista (CA-01)
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE general.usp_Configuracion_Listar
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  ideConfiguracion,
            txtCodigoConfiguracion,
            numParametro,
            txtParametro,
            numMinimo,
            numMaximo,
            txtDescripcion
    FROM general.TG_CONFIGURACION
    WHERE flgEstado = 1
    ORDER BY ideConfiguracion;
END
GO

/* ---------------------------------------------------------------------------
   Lectura puntual: el caso de uso la necesita antes de actualizar para poder
   auditar el valor anterior (CA-03).
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE general.usp_Configuracion_ObtenerPorCodigo
    @txtCodigoConfiguracion varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  ideConfiguracion,
            txtCodigoConfiguracion,
            numParametro,
            txtParametro,
            numMinimo,
            numMaximo,
            txtDescripcion
    FROM general.TG_CONFIGURACION
    WHERE txtCodigoConfiguracion = @txtCodigoConfiguracion
      AND flgEstado = 1;
END
GO

/* ---------------------------------------------------------------------------
   Actualizacion del valor (CA-02).

   Llega con valor uno solo de los dos parametros de valor; el COALESCE deja
   intacta la columna que viene en NULL, para que un entero no pise el texto de
   un porcentaje ni al reves. El rango y la descripcion no se tocan: se
   administran desde la base de datos.
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE general.usp_Configuracion_Actualizar
    @txtCodigoConfiguracion varchar(30),
    @numParametro           int          = NULL,
    @txtParametro           varchar(100) = NULL,
    @txtUsuario             varchar(30)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE general.TG_CONFIGURACION
    SET numParametro            = COALESCE(@numParametro, numParametro),
        txtParametro            = COALESCE(@txtParametro, txtParametro),
        fecActualizacion        = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE txtCodigoConfiguracion = @txtCodigoConfiguracion
      AND flgEstado = 1;

    IF @@ROWCOUNT = 0
        THROW 50003, 'La configuracion indicada no existe o fue desactivada.', 1;
END
GO
