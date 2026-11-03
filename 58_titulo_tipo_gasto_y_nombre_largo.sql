/* =========================================================================
   58 - Correcciones: titulo del tipo de gasto y nombre largo de proyectos

   1. La opcion de menu "Tipo de gasto de personal" pasa a llamarse "Tipo de
      gasto". El codigo de la opcion y su ruta no cambian.

   2. Las busquedas de proyectos devuelven tambien el nombre largo de SPRING
      (afemst.localname), porque hay nombres cortos repetidos. Alcance segun
      el pedido: solo las busquedas y el listado de actualizacion de estado
      de proyectos. No entra en el procesamiento, los reportes ni las
      descargas a Excel.

   proceso.usp_ProyectoSpring_Listar recibe @flgNombreLargo para no romper a
   sus cinco llamadores: todos hacen INSERT INTO #spring (codProyecto,
   nomProyecto) EXEC, que exige que el numero de columnas calce. Con el valor
   por defecto siguen recibiendo dos columnas; quien necesita el nombre largo
   pide la tercera. Asi la consulta a afemst sigue viviendo en un solo sitio.

   El nombre largo se lee de SPRING en el momento, no se guarda: aparece de
   inmediato y no depende de volver a replicar el periodo.

   Nota: afemst.localname es char(1000), de ahi el varchar(1000).

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

/* -------------------------------------------------------------------------
   1. Titulo de la opcion de menu
   ------------------------------------------------------------------------- */

UPDATE seguridad.TG_OPCION
   SET nomOpcion = 'Tipo de gasto',
       fecActualizacion = SYSDATETIME(),
       txtUsuarioActualizacion = 'SYSTEM_COSTOLABOR'
WHERE codOpcion = 'TIPO_GASTO_PERSONAL'
  AND nomOpcion <> 'Tipo de gasto';
GO

/* -------------------------------------------------------------------------
   2. Maestro de proyectos de SPRING, con el nombre largo opcional

   Reemplaza al del script 45. Vacio si BD_SPRING no esta disponible, con las
   mismas columnas que habria devuelto.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ProyectoSpring_Listar
    @flgNombreLargo bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
    BEGIN
        IF @flgNombreLargo = 1
            SELECT CAST(NULL AS varchar(30))  AS codProyecto,
                   CAST(NULL AS varchar(200)) AS nomProyecto,
                   CAST(NULL AS varchar(1000)) AS nomProyectoLargo
            WHERE 1 = 0;
        ELSE
            SELECT CAST(NULL AS varchar(30))  AS codProyecto,
                   CAST(NULL AS varchar(200)) AS nomProyecto
            WHERE 1 = 0;
        RETURN;
    END

    IF @flgNombreLargo = 1
        EXEC sp_executesql N'
            SELECT codProyecto, nomProyecto, nomProyectoLargo
            FROM (
                SELECT CAST(TRIM(afe) AS varchar(30)) AS codProyecto,
                       CAST(TRIM(englishname) AS varchar(200)) AS nomProyecto,
                       NULLIF(CAST(TRIM(localname) AS varchar(1000)), '''') AS nomProyectoLargo,
                       ROW_NUMBER() OVER (PARTITION BY TRIM(afe) ORDER BY englishname) AS numOrden
                FROM BD_SPRING.dbo.afemst
                WHERE afe IS NOT NULL AND englishname IS NOT NULL
            ) a
            WHERE numOrden = 1;';
    ELSE
        EXEC sp_executesql N'
            SELECT codProyecto, nomProyecto
            FROM (
                SELECT CAST(TRIM(afe) AS varchar(30)) AS codProyecto,
                       CAST(TRIM(englishname) AS varchar(200)) AS nomProyecto,
                       ROW_NUMBER() OVER (PARTITION BY TRIM(afe) ORDER BY englishname) AS numOrden
                FROM BD_SPRING.dbo.afemst
                WHERE afe IS NOT NULL AND englishname IS NOT NULL
            ) a
            WHERE numOrden = 1;';
END
GO

/* -------------------------------------------------------------------------
   3. Busqueda de proyectos de SPRING para excluir

   Reemplaza a la del script 50. Igual que antes, salvo que devuelve el
   nombre largo y que tambien busca por el.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ProyectoExcluido_Buscar
    @numAnio     int,
    @numMes      int,
    @txtCriterio varchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- El criterio es texto literal: sus comodines de LIKE no cuentan como tales.
    DECLARE @patron varchar(400) =
        '%' + REPLACE(REPLACE(REPLACE(ISNULL(TRIM(@txtCriterio), ''), '[', '[[]'), '%', '[%]'), '_', '[_]') + '%';

    CREATE TABLE #spring (codProyecto      varchar(30)   NOT NULL PRIMARY KEY,
                          nomProyecto      varchar(200)  NOT NULL,
                          nomProyectoLargo varchar(1000) NULL);
    INSERT INTO #spring (codProyecto, nomProyecto, nomProyectoLargo)
        EXEC proceso.usp_ProyectoSpring_Listar @flgNombreLargo = 1;

    SELECT TOP (50) s.codProyecto, s.nomProyecto, s.nomProyectoLargo
    FROM #spring s
    WHERE LEN(s.codProyecto) <= 12
      AND (s.codProyecto LIKE @patron
           OR s.nomProyecto COLLATE Latin1_General_CI_AI LIKE @patron COLLATE Latin1_General_CI_AI
           OR s.nomProyectoLargo COLLATE Latin1_General_CI_AI LIKE @patron COLLATE Latin1_General_CI_AI)
      AND NOT EXISTS (SELECT 1 FROM proceso.TMD_PROYECTO_EXCLUIDO e
                      WHERE e.numAnio = @numAnio AND e.numMes = @numMes
                        AND e.codProyecto = s.codProyecto AND e.flgEstado = 1)
    ORDER BY s.nomProyecto, s.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   4. Listado de actualizacion de estado de proyectos

   Reemplaza al del script 36. Mismos dos conjuntos de resultados; el de los
   proyectos suma el nombre largo, tomado de SPRING en el momento. Si
   BD_SPRING no esta disponible el nombre largo viene nulo y el listado
   sigue funcionando.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_EstadoProyecto_Listar
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
                     THEN 1 ELSE 0 END AS bit) AS flgCerrado,
           COUNT(e.ideEstadoProyecto) AS numTotal,
           COUNT(CASE WHEN e.ideEstadoProyecto IS NOT NULL AND e.flgActivoCostoLabor IS NULL THEN 1 END) AS numSinEstado
    FROM (SELECT 1 AS uno) u
    LEFT JOIN proceso.TMD_ESTADO_PROYECTO e
           ON e.numAnio = @numAnio AND e.numMes = @numMes AND e.flgEstado = 1;

    CREATE TABLE #spring (codProyecto      varchar(30)   NOT NULL PRIMARY KEY,
                          nomProyecto      varchar(200)  NOT NULL,
                          nomProyectoLargo varchar(1000) NULL);
    INSERT INTO #spring (codProyecto, nomProyecto, nomProyectoLargo)
        EXEC proceso.usp_ProyectoSpring_Listar @flgNombreLargo = 1;

    SELECT e.ideEstadoProyecto, e.codProyecto, e.nomProyecto, s.nomProyectoLargo,
           e.fecAprobadoSpring, e.fecInicioSpring, e.fecFinSpring, e.txtEstadoSpring,
           e.flgActivoCostoLabor
    FROM proceso.TMD_ESTADO_PROYECTO e
    LEFT JOIN #spring s ON s.codProyecto = e.codProyecto
    WHERE e.numAnio = @numAnio AND e.numMes = @numMes AND e.flgEstado = 1
    ORDER BY e.nomProyecto, e.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   5. Catalogo de proyectos del registro de horas

   Reemplaza al del script 36. Los proyectos siguen saliendo de los activos
   del periodo; el nombre largo se agrega para distinguir los nombres cortos
   repetidos al buscarlos.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_Proyecto_ListarCatalogo
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #spring (codProyecto      varchar(30)   NOT NULL PRIMARY KEY,
                          nomProyecto      varchar(200)  NOT NULL,
                          nomProyectoLargo varchar(1000) NULL);
    INSERT INTO #spring (codProyecto, nomProyecto, nomProyectoLargo)
        EXEC proceso.usp_ProyectoSpring_Listar @flgNombreLargo = 1;

    SELECT e.codProyecto, e.nomProyecto, s.nomProyectoLargo
    FROM proceso.TMD_ESTADO_PROYECTO e
    LEFT JOIN #spring s ON s.codProyecto = e.codProyecto
    WHERE e.numAnio = @numAnio AND e.numMes = @numMes
      AND e.flgEstado = 1 AND e.flgActivoCostoLabor = 1
    ORDER BY e.nomProyecto, e.codProyecto;
END
GO
