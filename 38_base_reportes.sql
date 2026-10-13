/* =========================================================================
   38 - Base comun de los reportes (HU-009 a HU-014)

   Lo que comparten todos los reportes:

     - registro.usp_Periodo_ListarCerrados: los selectores de anio y mes solo
       ofrecen periodos cerrados (registro.TMC_PERIODO.flgEstado = 2).
     - proceso.usp_Reporte_ListarFuentes: las fuentes de financiamiento del
       filtro "Fte. Fto." (HU-009 y HU-010) son las categorias con las que se
       proceso la compensacion del periodo.
     - Las opciones de menu de cada reporte y los perfiles que las ven, segun
       el CA de seguridad de cada historia:

         HU-009 Gasto operativo            CONTADOR
         HU-010 Compensacion               CONTADOR, JEFE, ADMINISTRADOR
         HU-011 Consolidado                CONTADOR, JEFE, SUPERVISOR, ADMINISTRADOR
         HU-012 Proyecto de resolucion     CONTADOR, JEFE, ADMINISTRADOR
         HU-013 Detalle por dia            CONTADOR, JEFE, SUPERVISOR, ADMINISTRADOR
         HU-014 Detalle por mes            CONTADOR, JEFE, ADMINISTRADOR

       Los jefes de la Gerencia de Operaciones y de la GIP y el Gerente de
       Inversion Privada usan el perfil JEFE.

     - REP_MANO_OBRA ("Costo de mano de obra") se da de baja: ninguna historia
       la define y su pantalla no existe; la mano de obra sale en el
       consolidado del procesamiento (HU-008).

   La auditoria de cada consulta y descarga usa general.usp_Auditoria_Registrar,
   que ya existe.

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

/* ---------------------------------------------------------------------------
   Periodos cerrados, del mas reciente al mas antiguo.
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE registro.usp_Periodo_ListarCerrados
AS
BEGIN
    SET NOCOUNT ON;

    SELECT numAnio, numMes
    FROM registro.TMC_PERIODO
    WHERE flgEstado = 2
    ORDER BY numAnio DESC, numMes DESC;
END
GO

/* ---------------------------------------------------------------------------
   Fuentes de financiamiento del periodo: las categorias que quedaron en la
   distribucion de la compensacion al procesarlo. "Categoria Desconocida" no
   es una fuente: es la marca de los proyectos sin categoria, y sus montos
   solo aparecen con el filtro "Todas".
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE proceso.usp_Reporte_ListarFuentes
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT TRIM(dc.txtCategoria) AS codFuente
    FROM proceso.TMD_DISTRIBUCION_COMPENSACION dc
    JOIN registro.TMC_PERIODO p ON p.idePeriodo = dc.idePeriodo
    WHERE p.numAnio = @numAnio
      AND p.numMes = @numMes
      AND dc.flgEstado = 1
      AND NULLIF(TRIM(dc.txtCategoria), '') IS NOT NULL
      AND dc.txtCategoria <> 'Categoria Desconocida'
    ORDER BY codFuente;
END
GO

/* ---------------------------------------------------------------------------
   Opciones de menu de los reportes. Las que ya existian (script 08) se
   ordenan y se nombran por su historia; las del detalle por dia y por mes
   son nuevas.
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

DECLARE @opciones TABLE (
    codOpcion varchar(50)  NOT NULL,
    nomOpcion varchar(100) NOT NULL,
    txtRuta   varchar(200) NOT NULL,
    txtIcono  varchar(50)  NOT NULL,
    numOrden  int          NOT NULL
);

INSERT INTO @opciones VALUES
   ('REP_GASTO_OPERATIVO', 'Gasto operativo por proyecto',      '/reportes/gasto-operativo',     'bi bi-bar-chart',         1),
   ('REP_COMPENSACION',    'Compensación por proyecto',         '/reportes/compensacion',        'bi bi-bar-chart',         2),
   ('REP_CONSOLIDADO',     'Consolidado de costo labor',        '/reportes/consolidado',         'bi bi-table',             3),
   ('PROY_RESOLUCION',     'Proyecto de resolución',            '/reportes/proyecto-resolucion', 'bi bi-file-earmark-word', 4),
   ('REP_DETALLE_DIA',     'Detallado por día',                '/reportes/detalle-dia',         'bi bi-calendar-day',      5),
   ('REP_DETALLE_MES',     'Detallado por mes',                '/reportes/detalle-mes',         'bi bi-calendar-month',    6);

UPDATE o
SET o.nomOpcion = d.nomOpcion,
    o.txtRuta = d.txtRuta,
    o.txtIcono = d.txtIcono,
    o.numOrden = d.numOrden,
    o.flgEstado = 1,
    o.fecActualizacion = GETDATE(),
    o.txtUsuarioActualizacion = @usuario
FROM seguridad.TG_OPCION o
JOIN @opciones d ON d.codOpcion = o.codOpcion
WHERE o.nomOpcion <> d.nomOpcion OR o.txtRuta <> d.txtRuta OR o.txtIcono <> d.txtIcono
   OR o.numOrden <> d.numOrden OR o.flgEstado <> 1;

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT d.codOpcion, d.nomOpcion, d.txtRuta, d.txtIcono, p.ideOpcion, d.numOrden, 1, @usuario
FROM @opciones d
JOIN seguridad.TG_OPCION p ON p.codOpcion = 'REPORTES'
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION o WHERE o.codOpcion = d.codOpcion);

-- Sin historia ni pantalla: se retira del menu de todos los perfiles.
UPDATE seguridad.TG_OPCION
SET flgEstado = 0, fecActualizacion = GETDATE(), txtUsuarioActualizacion = @usuario
WHERE codOpcion = 'REP_MANO_OBRA' AND flgEstado <> 0;
GO

/* ---------------------------------------------------------------------------
   Los scripts 36 y 37 se guardaron sin BOM y, corridos con sqlcmd, dejaron
   las tildes de sus opciones de menu como dos caracteres. Se corrigen aqui
   para las bases donde ya se aplicaron.
   --------------------------------------------------------------------------- */
UPDATE seguridad.TG_OPCION
SET nomOpcion = 'Actualización de estado de proyectos', fecActualizacion = GETDATE(),
    txtUsuarioActualizacion = 'SYSTEM_COSTOLABOR'
WHERE codOpcion = 'ESTADO_PROYECTOS' AND nomOpcion <> 'Actualización de estado de proyectos';

UPDATE seguridad.TG_OPCION
SET nomOpcion = 'Categorización de proyectos', fecActualizacion = GETDATE(),
    txtUsuarioActualizacion = 'SYSTEM_COSTOLABOR'
WHERE codOpcion = 'CATEGORIZACION_PROYECTOS' AND nomOpcion <> 'Categorización de proyectos';
GO

/* ---------------------------------------------------------------------------
   Perfiles de cada reporte. Solo agrega las asignaciones que nunca
   existieron: si el administrador quito una desde Perfiles y permisos, volver
   a correr el script no la repone.
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

DECLARE @asignaciones TABLE (codPerfil varchar(30) NOT NULL, codOpcion varchar(50) NOT NULL);

INSERT INTO @asignaciones (codPerfil, codOpcion)
SELECT a.codPerfil, a.codOpcion
FROM (VALUES
   ('CONTADOR',      'REP_GASTO_OPERATIVO'),

   ('CONTADOR',      'REP_COMPENSACION'),
   ('JEFE',          'REP_COMPENSACION'),
   ('ADMINISTRADOR', 'REP_COMPENSACION'),

   ('CONTADOR',      'REP_CONSOLIDADO'),
   ('JEFE',          'REP_CONSOLIDADO'),
   ('SUPERVISOR',    'REP_CONSOLIDADO'),
   ('ADMINISTRADOR', 'REP_CONSOLIDADO'),

   ('CONTADOR',      'PROY_RESOLUCION'),
   ('JEFE',          'PROY_RESOLUCION'),
   ('ADMINISTRADOR', 'PROY_RESOLUCION'),

   ('CONTADOR',      'REP_DETALLE_DIA'),
   ('JEFE',          'REP_DETALLE_DIA'),
   ('SUPERVISOR',    'REP_DETALLE_DIA'),
   ('ADMINISTRADOR', 'REP_DETALLE_DIA'),

   ('CONTADOR',      'REP_DETALLE_MES'),
   ('JEFE',          'REP_DETALLE_MES'),
   ('ADMINISTRADOR', 'REP_DETALLE_MES')
) AS a(codPerfil, codOpcion);

-- Quien ve algun reporte necesita el menu padre.
INSERT INTO @asignaciones (codPerfil, codOpcion)
SELECT DISTINCT codPerfil, 'REPORTES' FROM @asignaciones;

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM @asignaciones a
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
