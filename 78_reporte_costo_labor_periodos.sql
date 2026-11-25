/* =========================================================================
   78 - Reporte "Costo labor por periodos y fuente"

   Reproduce la hoja "RESUMEN CL+RENT+IGV" del Excel del contador: por fuente
   y proyecto, para un rango de meses cerrados de un mismo anio, la mano de
   obra, el gasto operativo y la compensacion de cada mes, y en el total del
   rango ademas la rentabilidad y el IGV.

     codOpcion       ruta                              perfiles
     COSTO_PERIODOS  /reportes/costo-labor-periodos    CONTADOR, JEFE, ADMINISTRADOR

   Los datos salen de proceso.usp_Reporte_CostoLabor (modo
   RESOLUCION_COSTO_LABOR), de la categorizacion de proyectos vigente y de la
   rentabilidad registrada: aqui no cambia ningun objeto de la base.

   La opcion va justo despues del proyecto de resolucion: las opciones de
   REPORTES que estan despues bajan un lugar (solo la vez que se agrega).

   Errores nuevos:
     50149  falta la opcion REPORTES o PROY_RESOLUCION (scripts 08 y 39)

   Idempotente. Igual que el script 56: la opcion y cada asignacion solo se
   agregan si nunca existieron, para no devolverle el reporte a un perfil al
   que el administrador se lo quito.
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
   OR NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'PROY_RESOLUCION')
    THROW 50149, 'Faltan las opciones REPORTES o PROY_RESOLUCION en seguridad.TG_OPCION (scripts 08 y 39).', 1;
GO

/* ---------------------------------------------------------------------------
   Opcion de menu, despues del proyecto de resolucion.
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

IF NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'COSTO_PERIODOS')
BEGIN
    BEGIN TRANSACTION;

    DECLARE @idePadre bigint, @orden int;
    SELECT @idePadre = o.ideOpcionPadre, @orden = o.numOrden + 1
    FROM seguridad.TG_OPCION o
    WHERE o.codOpcion = 'PROY_RESOLUCION';

    UPDATE seguridad.TG_OPCION
    SET numOrden = numOrden + 1,
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = @usuario
    WHERE ideOpcionPadre = @idePadre AND numOrden >= @orden;

    INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
    VALUES ('COSTO_PERIODOS', 'Costo labor por periodos', '/reportes/costo-labor-periodos', 'bi bi-table',
            @idePadre, @orden, 1, @usuario);

    COMMIT TRANSACTION;
END;
GO

/* ---------------------------------------------------------------------------
   Perfiles del reporte. El titulo REPORTES va con cada perfil: sin el, el
   menu descarta sus opciones.
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('CONTADOR'), ('JEFE'), ('ADMINISTRADOR')) AS a(codPerfil)
CROSS JOIN (VALUES ('REPORTES'), ('COSTO_PERIODOS')) AS r(codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = r.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
