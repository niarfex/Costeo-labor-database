/* Resolucion del empleado a partir del usuario autenticado - HU-005 */

USE [COSTO_LABOR];
GO

-- La grilla de horas trabaja con ideEmpleado, pero el token solo trae el usuario.
-- El vinculo lo guarda seguridad.TMD_PERFIL_USUARIO.ideEmpleado (script 13).
CREATE OR ALTER PROCEDURE seguridad.usp_Empleado_ObtenerPorUsuario
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1) pu.ideEmpleado
    FROM seguridad.TMD_PERFIL_USUARIO pu
    WHERE pu.txtUsuario = @txtUsuario
      AND pu.ideEmpleado IS NOT NULL
      AND pu.flgEstado = 1;
END
GO
