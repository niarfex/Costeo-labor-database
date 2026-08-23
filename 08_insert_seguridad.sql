/* ============================================================================
   HU-003 - Datos iniciales de seguridad.

   Los perfiles salen de la seccion PERFILES del documento funcional.
   El catalogo de opciones sale de las historias de usuario HU-002 a HU-011.
   ============================================================================ */

USE [COSTO_LABOR];
GO

/* Las tablas de seguridad tienen indices filtrados: SQL Server exige estas
   opciones tambien para INSERT y UPDATE, no solo para crear el indice.
   sqlcmd las trae en OFF por defecto, de ahi que el script las fije. */
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

/* ---------------------------------------------------------------------------
   Perfiles (seccion PERFILES del documento funcional)
   --------------------------------------------------------------------------- */
INSERT INTO seguridad.TMC_PERFIL (codPerfil, nomPerfil, txtDescripcion, flgEstado, txtUsuarioCreacion) VALUES
 ('ADMINISTRADOR',        'Administrador del sistema',   'Configuracion y parametrizacion del sistema de costo labor', 1, @usuario),
 ('RESPONSABLE_REGISTRO', 'Responsable de registro',     'Registra mensualmente las horas trabajadas por proyecto',     1, @usuario),
 ('TRABAJADOR',           'Trabajador',                  'Registra diariamente sus horas trabajadas por proyecto',      1, @usuario),
 ('JEFE',                 'Jefe de gerencia',            'Supervisa y valida las horas de su personal a cargo',         1, @usuario),
 ('SUPERVISOR',           'Supervisor de proyectos',     'Revisa la consistencia y realiza el cierre mensual',          1, @usuario),
 ('CONTADOR',             'Contador',                    'Responsable de la ejecucion y cierre del costo labor',        1, @usuario);
GO

/* ---------------------------------------------------------------------------
   Opciones de primer nivel (titulos del menu)
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion) VALUES
 ('SEGURIDAD',     'Seguridad',      NULL, 'bi bi-shield-lock',            NULL, 1, 1, @usuario),
 ('MANTENIMIENTO', 'Mantenimiento',  NULL, 'bi bi-tools',                  NULL, 2, 1, @usuario),
 ('COSTO_LABOR',   'Costo labor',    NULL, 'bi bi-clock-history',          NULL, 3, 1, @usuario),
 ('REPORTES',      'Reportes',       NULL, 'bi bi-file-earmark-bar-graph', NULL, 4, 1, @usuario);
GO

/* ---------------------------------------------------------------------------
   Sub-opciones, una por historia de usuario
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT d.codOpcion, d.nomOpcion, d.txtRuta, d.txtIcono, p.ideOpcion, d.numOrden, 1, @usuario
FROM (VALUES
   -- HU-003
   ('PERFILES',            'Perfiles y permisos',        '/seguridad/perfiles',              'bi bi-people',            'SEGURIDAD',     1),
   -- HU-002
   ('CONFIGURACION',       'Configuraciones generales',  '/mantenimiento/configuracion',     'bi bi-sliders',           'MANTENIMIENTO', 1),
   -- HU-004
   ('PARAMETRIZACION',     'Parametrizacion de campos',  '/mantenimiento/parametrizacion',   'bi bi-diagram-3',         'MANTENIMIENTO', 2),
   -- HU-005
   ('HORAS_DIA',           'Registro de horas por dia',  '/costo-labor/horas-dia',           'bi bi-calendar-day',      'COSTO_LABOR',   1),
   -- HU-006
   ('HORAS_MES',           'Registro de horas por mes',  '/costo-labor/horas-mes',           'bi bi-calendar-month',    'COSTO_LABOR',   2),
   -- HU-007 a HU-011
   ('REP_MANO_OBRA',       'Costo de mano de obra',      '/reportes/mano-obra',              'bi bi-bar-chart',         'REPORTES',      1),
   ('REP_GASTO_OPERATIVO', 'Gasto operativo',            '/reportes/gasto-operativo',        'bi bi-bar-chart',         'REPORTES',      2),
   ('REP_COMPENSACION',    'Compensacion por proyecto',  '/reportes/compensacion',           'bi bi-bar-chart',         'REPORTES',      3),
   ('REP_CONSOLIDADO',     'Consolidado de costo labor', '/reportes/consolidado',            'bi bi-bar-chart',         'REPORTES',      4),
   ('PROY_RESOLUCION',     'Proyecto de resolucion',     '/reportes/proyecto-resolucion',    'bi bi-file-earmark-word', 'REPORTES',      5)
) AS d(codOpcion, nomOpcion, txtRuta, txtIcono, codPadre, numOrden)
JOIN seguridad.TG_OPCION p ON p.codOpcion = d.codPadre;
GO

/* ---------------------------------------------------------------------------
   Asignacion de opciones por perfil, segun las funciones que describe el
   documento funcional para cada rol.
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES
   ('ADMINISTRADOR',        'SEGURIDAD'),     ('ADMINISTRADOR',        'PERFILES'),
   ('ADMINISTRADOR',        'MANTENIMIENTO'), ('ADMINISTRADOR',        'CONFIGURACION'),
   ('ADMINISTRADOR',        'PARAMETRIZACION'),

   ('TRABAJADOR',           'COSTO_LABOR'),   ('TRABAJADOR',           'HORAS_DIA'),

   ('RESPONSABLE_REGISTRO', 'COSTO_LABOR'),   ('RESPONSABLE_REGISTRO', 'HORAS_MES'),

   ('JEFE',                 'COSTO_LABOR'),   ('JEFE',                 'HORAS_DIA'),
   ('JEFE',                 'HORAS_MES'),

   ('SUPERVISOR',           'COSTO_LABOR'),   ('SUPERVISOR',           'HORAS_MES'),
   ('SUPERVISOR',           'REPORTES'),      ('SUPERVISOR',           'REP_CONSOLIDADO'),

   ('CONTADOR',             'REPORTES'),      ('CONTADOR',             'REP_MANO_OBRA'),
   ('CONTADOR',             'REP_GASTO_OPERATIVO'), ('CONTADOR',       'REP_COMPENSACION'),
   ('CONTADOR',             'REP_CONSOLIDADO'),     ('CONTADOR',       'PROY_RESOLUCION')
) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION   op ON op.codOpcion = a.codOpcion;
GO

/* ---------------------------------------------------------------------------
   Usuario administrador inicial. Es la cuenta del proyecto en Entra ID, la
   unica disponible hoy; el resto se asigna desde la pantalla de la HU-003.
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_USUARIO (idePerfil, txtUsuario, txtNombreCompleto, flgEstado, txtUsuarioCreacion)
SELECT idePerfil, 'soporte.costolabor@amsac.pe', 'Soporte Costo Labor', 1, @usuario
FROM seguridad.TMC_PERFIL WHERE codPerfil = 'ADMINISTRADOR';
GO
