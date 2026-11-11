/* =========================================================================
   65 - Asignacion de areas: cesados con gastos en el periodo

   Conserva el personal elegible del script 52 e incluye a los empleados
   cesados que tengan gastos activos en el periodo seleccionado. Un gasto
   de otro mes o dado de baja no habilita a la persona. EXISTS evita repetir
   personas con varias lineas de gasto.

   Solo cambia el catalogo de asignacion de areas. El registro de horas
   conserva su regla de cese. No modifica BD_SPRING, fechas de cese,
   asignaciones ni importes. Requiere los scripts anteriores (hasta 64).
   Idempotente; ejecutar completo en COSTO_LABOR.
   ========================================================================= */

USE [COSTO_LABOR];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE registro.usp_PersonalSpring_ListarPeriodo
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        SELECT CAST(NULL AS bigint) AS idePersona, CAST(NULL AS varchar(150)) AS txtNombreCompleto,
               CAST(NULL AS varchar(20)) AS Documento, CAST(NULL AS varchar(200)) AS Area,
               CAST(NULL AS varchar(200)) AS Departamento, CAST(NULL AS varchar(200)) AS Cargo
        WHERE 1 = 0;
        RETURN;
    END

    DECLARE @idePeriodo bigint = (SELECT idePeriodo FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes);

    EXEC sp_executesql N'
        SELECT DISTINCT
            CAST(pm.Persona AS bigint) AS idePersona,
            TRIM(pm.NombreCompleto) AS txtNombreCompleto,
            TRIM(pm.Documento) AS Documento,
            hrdiv.DescripcionLarga AS Area,
            hrdep.Descripcion AS Departamento,
            hre.Descripcion AS Cargo
        FROM BD_SPRING.dbo.PersonaMast AS pm
        LEFT JOIN BD_SPRING.dbo.EmpleadoMast AS em ON em.Empleado = pm.Persona
        LEFT JOIN BD_SPRING.dbo.HR_PuestoEmpresa AS hre ON hre.CodigoPuesto = em.CodigoCargo
        LEFT JOIN BD_SPRING.dbo.HR_Departamento AS hrdep ON hrdep.Departamento = em.DepartamentoOperacional
        LEFT JOIN BD_SPRING.dbo.HR_Division AS hrdiv ON hrdiv.Division = em.Division
        WHERE em.Empleado IS NOT NULL
          AND (em.FechaCese IS NULL
               OR @anio_actual * 100 + @mes_actual <= YEAR(em.FechaCese) * 100 + MONTH(em.FechaCese)
               OR EXISTS (SELECT 1 FROM proceso.TMD_GASTO_PERSONAL g
                          WHERE g.idePeriodo = @periodo AND g.vendor = pm.Persona
                            AND g.flgEstado = 1))
        ORDER BY txtNombreCompleto;',
        N'@mes_actual int, @anio_actual int, @periodo bigint',
        @mes_actual = @numMes, @anio_actual = @numAnio, @periodo = @idePeriodo;
END
GO
