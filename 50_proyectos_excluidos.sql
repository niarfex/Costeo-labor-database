/* =========================================================================
   50 - Proyectos excluidos del calculo del costo labor

   El Contador indica por periodo (anio y mes) que proyectos de SPRING quedan
   fuera del calculo del costo labor. Las lineas de esos proyectos se cargan
   igual en proceso.TMD_GASTO_PERSONAL; la exclusion se aplica en los cuadros
   que se calculan a partir de ella. Reemplaza al filtro fijo del proyecto
   000000505049 que tenia el llenado del gasto de personal.

   Los proyectos se buscan en SPRING (afemst) con la consulta de referencia
   del script 45 y se guarda una copia del nombre: el periodo cerrado sigue
   mostrando el de entonces. Quitar un proyecto es una baja logica.
   "Obtener del periodo anterior" copia los excluidos del ultimo periodo
   anterior que los tenga.

   Precarga: 000000505049 en enero 2025 y, para no cambiar los resultados ya
   obtenidos con el filtro fijo, en cada periodo de registro.TMC_PERIODO desde
   enero 2025 que todavia no tenga exclusiones. Un periodo que ya tuvo alguna,
   aunque se haya quitado, no se vuelve a precargar.

   La opcion exige su marca de registros completados (script 43).

   Errores nuevos:
     50130  el periodo esta cerrado
     50131  el proyecto no existe en SPRING (o SPRING no esta disponible)
     50132  el proyecto ya esta excluido en el periodo
     50133  la exclusion no existe

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

-- Las mismas opciones que exigen el indice filtrado al crearlo y al insertar.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* -------------------------------------------------------------------------
   1. Tabla e indice
   ------------------------------------------------------------------------- */

IF OBJECT_ID('proceso.TMD_PROYECTO_EXCLUIDO') IS NULL
BEGIN
    -- codProyecto es el afe de SPRING sin espacios: el calculo lo compara con
    -- TRIM(afe) de proceso.TMD_GASTO_PERSONAL.
    CREATE TABLE proceso.TMD_PROYECTO_EXCLUIDO(
        ideProyectoExcluido bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        codProyecto varchar(12) NOT NULL,
        nomProyecto varchar(500) NULL,
        txtMotivo varchar(500) NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMD_PROYECTO_EXCLUIDO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_PROYECTO_EXCLUIDO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMD_PROYECTO_EXCLUIDO PRIMARY KEY CLUSTERED (ideProyectoExcluido ASC)
    );
END
GO

-- Un proyecto activo una sola vez por periodo. Tambien es el indice por el que
-- el calculo busca los excluidos del periodo.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('proceso.TMD_PROYECTO_EXCLUIDO')
                 AND name = 'UX_TMD_PROYECTO_EXCLUIDO_PERIODO')
    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_PROYECTO_EXCLUIDO_PERIODO
        ON proceso.TMD_PROYECTO_EXCLUIDO (numAnio, numMes, codProyecto) WHERE flgEstado = 1;
GO

/* -------------------------------------------------------------------------
   2. Listado del periodo

   Dos conjuntos: si el periodo esta cerrado y los proyectos excluidos.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ProyectoExcluido_Listar
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
                     THEN 1 ELSE 0 END AS bit) AS flgCerrado;

    SELECT e.ideProyectoExcluido, e.codProyecto, e.nomProyecto, e.txtMotivo,
           e.txtUsuarioCreacion AS txtUsuario, e.fecCreacion AS fecRegistro
    FROM proceso.TMD_PROYECTO_EXCLUIDO e
    WHERE e.numAnio = @numAnio AND e.numMes = @numMes AND e.flgEstado = 1
    ORDER BY e.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   3. Busqueda de proyectos de SPRING para excluir

   Por codigo (basta una parte, como los seis ultimos digitos) o por nombre
   sin distinguir tildes, hasta 50 resultados. No ofrece los que ya estan
   excluidos en el periodo. Vacio si BD_SPRING no esta disponible.
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

    CREATE TABLE #spring (codProyecto varchar(30) NOT NULL PRIMARY KEY, nomProyecto varchar(200) NOT NULL);
    INSERT INTO #spring (codProyecto, nomProyecto) EXEC proceso.usp_ProyectoSpring_Listar;

    SELECT TOP (50) s.codProyecto, s.nomProyecto
    FROM #spring s
    WHERE LEN(s.codProyecto) <= 12
      AND (s.codProyecto LIKE @patron
           OR s.nomProyecto COLLATE Latin1_General_CI_AI LIKE @patron COLLATE Latin1_General_CI_AI)
      AND NOT EXISTS (SELECT 1 FROM proceso.TMD_PROYECTO_EXCLUIDO e
                      WHERE e.numAnio = @numAnio AND e.numMes = @numMes
                        AND e.codProyecto = s.codProyecto AND e.flgEstado = 1)
    ORDER BY s.nomProyecto, s.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   4. Agregar un proyecto al periodo
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ProyectoExcluido_Agregar
    @numAnio     int,
    @numMes      int,
    @codProyecto varchar(30),
    @txtMotivo   varchar(500) = NULL,
    @txtUsuario  varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50130, 'El periodo esta cerrado: sus proyectos excluidos no se pueden modificar.', 1;

    IF DB_ID('BD_SPRING') IS NULL
        THROW 50131, 'El proyecto no existe en SPRING (BD_SPRING no esta disponible).', 1;

    SET @codProyecto = TRIM(@codProyecto);

    CREATE TABLE #spring (codProyecto varchar(30) NOT NULL PRIMARY KEY, nomProyecto varchar(200) NOT NULL);
    INSERT INTO #spring (codProyecto, nomProyecto) EXEC proceso.usp_ProyectoSpring_Listar;

    DECLARE @nomProyecto varchar(200) =
        (SELECT nomProyecto FROM #spring WHERE codProyecto = @codProyecto AND LEN(codProyecto) <= 12);
    IF @nomProyecto IS NULL
        THROW 50131, 'El codigo de proyecto no existe en SPRING.', 1;

    IF EXISTS (SELECT 1 FROM proceso.TMD_PROYECTO_EXCLUIDO
               WHERE numAnio = @numAnio AND numMes = @numMes AND codProyecto = @codProyecto AND flgEstado = 1)
        THROW 50132, 'El proyecto ya esta excluido en el periodo.', 1;

    INSERT INTO proceso.TMD_PROYECTO_EXCLUIDO
           (numAnio, numMes, codProyecto, nomProyecto, txtMotivo, flgEstado, txtUsuarioCreacion)
    VALUES (@numAnio, @numMes, @codProyecto, @nomProyecto, NULLIF(TRIM(@txtMotivo), ''), 1, @txtUsuario);

    SELECT CAST(SCOPE_IDENTITY() AS bigint) AS ideProyectoExcluido;
END
GO

/* -------------------------------------------------------------------------
   5. Quitar un proyecto del periodo (baja logica)
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ProyectoExcluido_Quitar
    @ideProyectoExcluido bigint,
    @txtUsuario          varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @numAnio int, @numMes int;
    SELECT @numAnio = numAnio, @numMes = numMes
    FROM proceso.TMD_PROYECTO_EXCLUIDO
    WHERE ideProyectoExcluido = @ideProyectoExcluido AND flgEstado = 1;

    IF @numAnio IS NULL
        THROW 50133, 'El proyecto excluido indicado no existe.', 1;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50130, 'El periodo esta cerrado: sus proyectos excluidos no se pueden modificar.', 1;

    UPDATE proceso.TMD_PROYECTO_EXCLUIDO
    SET flgEstado = 0,
        fecActualizacion = GETDATE(),
        txtUsuarioActualizacion = @txtUsuario
    WHERE ideProyectoExcluido = @ideProyectoExcluido;
END
GO

/* -------------------------------------------------------------------------
   6. Obtener del periodo anterior

   Copia los excluidos del ultimo periodo anterior que los tenga (no
   necesariamente el mes previo), salvo los que ya estan en el periodo, con
   su nombre y motivo. Devuelve de donde copio y cuantos; sin periodo
   anterior con excluidos, el origen sale nulo y no copia nada.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_ProyectoExcluido_Replicar
    @numAnio    int,
    @numMes     int,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50130, 'El periodo esta cerrado: sus proyectos excluidos no se pueden modificar.', 1;

    DECLARE @numAnioOrigen int, @numMesOrigen int, @numCopiados int = 0;

    SELECT TOP (1) @numAnioOrigen = numAnio, @numMesOrigen = numMes
    FROM proceso.TMD_PROYECTO_EXCLUIDO
    WHERE flgEstado = 1 AND numAnio * 100 + numMes < @numAnio * 100 + @numMes
    ORDER BY numAnio DESC, numMes DESC;

    IF @numAnioOrigen IS NOT NULL
    BEGIN
        INSERT INTO proceso.TMD_PROYECTO_EXCLUIDO
               (numAnio, numMes, codProyecto, nomProyecto, txtMotivo, flgEstado, txtUsuarioCreacion)
        SELECT @numAnio, @numMes, o.codProyecto, o.nomProyecto, o.txtMotivo, 1, @txtUsuario
        FROM proceso.TMD_PROYECTO_EXCLUIDO o
        WHERE o.numAnio = @numAnioOrigen AND o.numMes = @numMesOrigen AND o.flgEstado = 1
          AND NOT EXISTS (SELECT 1 FROM proceso.TMD_PROYECTO_EXCLUIDO d
                          WHERE d.numAnio = @numAnio AND d.numMes = @numMes
                            AND d.codProyecto = o.codProyecto AND d.flgEstado = 1);
        SET @numCopiados = @@ROWCOUNT;
    END

    SELECT @numAnioOrigen AS numAnioOrigen, @numMesOrigen AS numMesOrigen, @numCopiados AS numCopiados;
END
GO

/* -------------------------------------------------------------------------
   7. Precarga del proyecto que excluia el filtro fijo

   Se inserta directo, sin el procedimiento de alta: enero 2025 esta cerrado
   y la precarga debe quedar tambien en los periodos cerrados. El nombre se
   toma de SPRING si esta disponible.
   ------------------------------------------------------------------------- */

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';
DECLARE @codProyecto varchar(12) = '000000505049';
DECLARE @nomProyecto varchar(500);

CREATE TABLE #spring (codProyecto varchar(30) NOT NULL PRIMARY KEY, nomProyecto varchar(200) NOT NULL);
INSERT INTO #spring (codProyecto, nomProyecto) EXEC proceso.usp_ProyectoSpring_Listar;

SET @nomProyecto = COALESCE((SELECT nomProyecto FROM #spring WHERE codProyecto = @codProyecto),
                            'INNOVACIÓN CON ENFOQUE SOSTENIBLE');

INSERT INTO proceso.TMD_PROYECTO_EXCLUIDO
       (numAnio, numMes, codProyecto, nomProyecto, txtMotivo, flgEstado, txtUsuarioCreacion)
SELECT p.numAnio, p.numMes, @codProyecto, @nomProyecto,
       'Proyecto de innovación que el cálculo del costo labor ya excluía.', 1, @usuario
FROM (
    SELECT 2025 AS numAnio, 1 AS numMes
    UNION
    SELECT numAnio, numMes FROM registro.TMC_PERIODO WHERE numAnio * 100 + numMes >= 202501
) p
WHERE NOT EXISTS (SELECT 1 FROM proceso.TMD_PROYECTO_EXCLUIDO e
                  WHERE e.numAnio = p.numAnio AND e.numMes = p.numMes);

DROP TABLE #spring;
GO

/* -------------------------------------------------------------------------
   8. Opcion de menu del Contador y marca de registros completados

   Igual que los scripts 33 y 36: idempotente y sin filtrar por flgEstado,
   para no devolver la opcion a un perfil al que el administrador se la quito.
   ------------------------------------------------------------------------- */

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'PROYECTOS_EXCLUIDOS', 'Proyectos excluidos', '/costo-labor/proyectos-excluidos',
       'bi bi-folder-x', p.ideOpcion, 11, 1, @usuario
FROM seguridad.TG_OPCION p
WHERE p.codOpcion = 'COSTO_LABOR'
  AND NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'PROYECTOS_EXCLUIDOS');

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('CONTADOR', 'COSTO_LABOR'), ('CONTADOR', 'PROYECTOS_EXCLUIDOS')) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);

INSERT INTO proceso.TMC_REGISTRO_PREVIO (codOpcion, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'PROYECTOS_EXCLUIDOS', 70, 1, @usuario
WHERE NOT EXISTS (SELECT 1 FROM proceso.TMC_REGISTRO_PREVIO
                  WHERE codOpcion = 'PROYECTOS_EXCLUIDOS' AND flgEstado = 1);
GO
