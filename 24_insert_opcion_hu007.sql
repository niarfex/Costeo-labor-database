/* =========================================================================
   HU-007 - Opcion de menu y permisos del registro de distribucion GIP

   08_insert_seguridad.sql no trae opcion para esta historia, por eso la
   pantalla no aparecia en el menu ni se podia habilitar desde la HU-003.

   El CA-05 restringe la vista al Gerente de Inversion Privada y al
   Administrador del sistema. El documento funcional agrupa al Gerente de
   Inversion Privada con el Supervisor de Gestion de Proyectos en un mismo
   rol, que en la semilla es el perfil SUPERVISOR.

   Idempotente. Los guardas no filtran por flgEstado a proposito: si el
   administrador ya quito la opcion de un perfil desde la HU-003, volver a
   correr el script no debe devolversela.
   ========================================================================= */

USE [COSTO_LABOR];
GO

/* Las tablas de seguridad tienen indices filtrados: SQL Server exige estas
   opciones tambien para INSERT y UPDATE, no solo para crear el indice. */
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* ---------------------------------------------------------------------------
   Opcion bajo el titulo Costo labor, despues del registro por dia y por mes
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'DISTRIBUCION_GIP', 'Distribucion de costos GIP', '/costo-labor/distribucion-gip',
       'bi bi-pie-chart', p.ideOpcion, 3, 1, @usuario
FROM seguridad.TG_OPCION p
WHERE p.codOpcion = 'COSTO_LABOR'
  AND NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'DISTRIBUCION_GIP');
GO

/* ---------------------------------------------------------------------------
   Asignacion a los perfiles del CA-05

   El titulo COSTO_LABOR se asigna junto con la opcion: el menu descarta las
   opciones cuyo titulo no llega en la lista del usuario, y el ADMINISTRADOR
   no lo tenia porque hasta ahora no registraba horas.
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES
   ('ADMINISTRADOR', 'COSTO_LABOR'), ('ADMINISTRADOR', 'DISTRIBUCION_GIP'),
   ('SUPERVISOR',    'COSTO_LABOR'), ('SUPERVISOR',    'DISTRIBUCION_GIP')
) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
