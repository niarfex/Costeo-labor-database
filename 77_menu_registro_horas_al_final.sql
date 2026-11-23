/* =========================================================================
   77 - Menu de Costo labor: el registro de horas va al final

   Pedido de los usuarios (23/11): en el menu "Costo labor", las opciones
   "Registro de horas por dia" y "Registro de horas por mes" pasan despues de
   las demas (procesamiento, configuraciones y exclusiones). El orden es el
   de la opcion, asi que vale para todos los perfiles que la ven.

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

UPDATE o
SET numOrden = CASE o.codOpcion WHEN 'HORAS_DIA' THEN 98 ELSE 99 END,
    fecActualizacion = GETDATE(),
    txtUsuarioActualizacion = @usuario
FROM seguridad.TG_OPCION o
JOIN seguridad.TG_OPCION p ON p.ideOpcion = o.ideOpcionPadre
WHERE p.codOpcion = 'COSTO_LABOR'
  AND o.codOpcion IN ('HORAS_DIA', 'HORAS_MES')
  AND o.numOrden <> CASE o.codOpcion WHEN 'HORAS_DIA' THEN 98 ELSE 99 END;
GO
