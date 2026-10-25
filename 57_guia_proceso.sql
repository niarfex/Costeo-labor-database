/* =========================================================================
   57 - Ayuda: guia del proceso

   Opcion de menu general "Ayuda > Guia del proceso", que explica como se
   calcula el costo labor, los registros previos paso a paso y de donde viene
   cada dato (BD_SPRING o la base de Costo Labor). La pagina es estatica en el
   frontend; aqui solo va la opcion, para todos los perfiles.

   Un perfil creado despues no la recibe solo: se le asigna desde la pantalla
   de perfiles, como cualquier otra opcion.

   Idempotente. Igual que los scripts 33 y 36: sin filtrar por flgEstado, para
   no devolver la opcion a un perfil al que el administrador se la quito.
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

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'AYUDA', 'Ayuda', NULL, 'bi bi-question-circle', NULL, 9, 1, @usuario
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'AYUDA');

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'GUIA_PROCESO', 'Guía del proceso', '/ayuda/guia', 'bi bi-signpost-split', p.ideOpcion, 1, 1, @usuario
FROM seguridad.TG_OPCION p
WHERE p.codOpcion = 'AYUDA'
  AND NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'GUIA_PROCESO');

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM seguridad.TMC_PERFIL pe
CROSS JOIN seguridad.TG_OPCION op
WHERE pe.flgEstado = 1
  AND op.codOpcion IN ('AYUDA', 'GUIA_PROCESO')
  AND NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
