/* Consulta de la parametrizacion vigente de un periodo - HU-004 leida desde HU-005 */

USE [COSTO_LABOR];
GO

-- El modal de captura de horas (CA-03 de la HU-005) se arma segun la
-- parametrizacion del periodo. usp_Parametro_Obtener resuelve por identificador
-- y usp_Parametro_Listar es paginado; ninguno sirve para buscar por anio y mes.
CREATE OR ALTER PROCEDURE registro.usp_Parametro_ObtenerPorPeriodo
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1)
           ideParametro,
           numAnio,
           numMes,
           flgRegActividad,
           flgRegTareaxActividad,
           flgRegComentarioxActividad,
           flgRegObservacionxTarea,
           flgRegObservacionxProyecto,
           flgRegObservacionxPeriodo,
           flgRegOtrosAtributos
    FROM registro.TMC_PARAMETRO
    WHERE numAnio = @numAnio
      AND numMes  = @numMes
      AND flgEstado = 1;
END
GO
