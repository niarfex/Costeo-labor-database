/* =========================================================================
   56 - Reportes con las hojas del Excel del procesamiento

   El procesamiento del periodo (y su Excel) es solo del Contador. Para que
   otros usuarios revisen el detalle, cada hoja se consulta tambien como
   reporte del menu Reportes, por periodo cerrado, con descarga en Excel y PDF:

     codOpcion                   ruta                                   hoja
     REP_RESUMEN_GRAL_GASTO      /reportes/resumen-gral-gasto-personal  RESUMEN_GRAL_GASTO_PERSONAL
     REP_DETALLE_GASTO_PERSONAL  /reportes/detalle-gasto-personal       DETALLE_GASTO_PERSONAL
     REP_RESUMEN_GASTO_PERSONAL  /reportes/resumen-gasto-personal       RESUMEN_GASTO_PERSONAL
     REP_RESUMEN_COSTO_LABOR     /reportes/resumen-costo-labor          RESUMEN_COSTO_LABOR
     REP_HH_POR_PROYECTO         /reportes/hh-por-proyecto              HH_POR_PROYECTO

   Los datos salen de proceso.usp_Reporte_CostoLabor, el mismo procedimiento
   del Excel del procesamiento: aqui no cambia ningun objeto de la base.
   codOpcion admite 30 caracteres; por eso el primero va abreviado.

   Perfiles: CONTADOR, JEFE y ADMINISTRADOR, los mismos de la compensacion y
   del proyecto de resolucion (script 39). El titulo REPORTES ya lo tienen
   (scripts 38 y 39); se vuelve a asegurar por si una base no lo tuviera.

   No llevan marca de registros completados: solo leen lo procesado.

   Errores nuevos:
     50148  falta la opcion REPORTES (script 08)

   Idempotente. Igual que los scripts 38 y 39: una opcion o una asignacion
   solo se agrega si nunca existio, para no devolverle un reporte a un
   perfil al que el administrador se lo quito.
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

IF NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'REPORTES')
    THROW 50148, 'Falta la opcion REPORTES en seguridad.TG_OPCION (script 08): los reportes van debajo de ella.', 1;
GO

/* ---------------------------------------------------------------------------
   Opciones de menu, despues de los reportes de horas (numOrden 6 y 7).
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT n.codOpcion, n.nomOpcion, n.txtRuta, n.txtIcono, p.ideOpcion, n.numOrden, 1, @usuario
FROM (VALUES
    ('REP_RESUMEN_GRAL_GASTO',     'Resumen general del gasto de personal', '/reportes/resumen-gral-gasto-personal', 'bi bi-table',            8),
    ('REP_DETALLE_GASTO_PERSONAL', 'Detalle del gasto de personal',         '/reportes/detalle-gasto-personal',      'bi bi-people',           9),
    ('REP_RESUMEN_GASTO_PERSONAL', 'Gasto de personal por gerencia',        '/reportes/resumen-gasto-personal',      'bi bi-diagram-3',       10),
    ('REP_RESUMEN_COSTO_LABOR',    'Resumen del costo labor',               '/reportes/resumen-costo-labor',         'bi bi-bar-chart-line',  11),
    ('REP_HH_POR_PROYECTO',        'Horas hombre por proyecto',             '/reportes/hh-por-proyecto',             'bi bi-clock-history',   12)
) AS n(codOpcion, nomOpcion, txtRuta, txtIcono, numOrden)
JOIN seguridad.TG_OPCION p ON p.codOpcion = 'REPORTES'
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION o WHERE o.codOpcion = n.codOpcion);
GO

/* ---------------------------------------------------------------------------
   Perfiles de cada reporte. El titulo REPORTES va con cada perfil: sin el,
   el menu descarta sus opciones.
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('CONTADOR'), ('JEFE'), ('ADMINISTRADOR')) AS a(codPerfil)
CROSS JOIN (VALUES ('REPORTES'),
                   ('REP_RESUMEN_GRAL_GASTO'),
                   ('REP_DETALLE_GASTO_PERSONAL'),
                   ('REP_RESUMEN_GASTO_PERSONAL'),
                   ('REP_RESUMEN_COSTO_LABOR'),
                   ('REP_HH_POR_PROYECTO')) AS r(codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = r.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
