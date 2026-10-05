/* =========================================================================
   33 - Gasto de personal no recuperable (documento del 27/09)

   El perfil Contador define por periodo grupos de personal cuyo gasto no se
   podra recuperar, cada uno con un nombre (por ejemplo TUCARI). El personal
   se busca en BD_SPRING con la consulta indicada por el lider, por nombre,
   cargo, area o departamento.

   Los grupos se reflejan en el reporte RESUMEN_GASTO_PERSONAL (script 34):
   una columna por grupo, y su gasto sale de lo que se reparte por proyecto.

   El grupo se guarda por anio y mes y no por idePeriodo: el periodo puede no
   existir todavia, porque lo crea el primer procesamiento.

   Errores nuevos:
     50070  el periodo esta cerrado
     50071  ya hay un grupo con ese nombre en el periodo
     50072  la persona ya esta en otro grupo del periodo
     50073  el grupo no existe
     50074  datos del grupo invalidos (nombre reservado o sin personal)
     50075  BD_SPRING no esta disponible

   Idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* -------------------------------------------------------------------------
   1. Tablas
   ------------------------------------------------------------------------- */

IF OBJECT_ID('proceso.TMC_GRUPO_NO_RECUPERABLE') IS NULL
BEGIN
    CREATE TABLE proceso.TMC_GRUPO_NO_RECUPERABLE(
        ideGrupoNoRecuperable bigint IDENTITY(1,1) NOT NULL,
        numAnio int NOT NULL,
        numMes int NOT NULL,
        nomGrupo varchar(100) NOT NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMC_GRUPO_NO_RECUPERABLE_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMC_GRUPO_NO_RECUPERABLE_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMC_GRUPO_NO_RECUPERABLE PRIMARY KEY CLUSTERED (ideGrupoNoRecuperable ASC)
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMC_GRUPO_NO_RECUPERABLE_NOMBRE
        ON proceso.TMC_GRUPO_NO_RECUPERABLE (numAnio, numMes, nomGrupo) WHERE flgEstado = 1;
END
GO

IF OBJECT_ID('proceso.TMD_GRUPO_NO_RECUPERABLE_PERSONA') IS NULL
BEGIN
    -- Los datos de la persona se copian de SPRING al asignarla: el grupo de un
    -- periodo cerrado debe seguir mostrando a quien se asigno entonces.
    CREATE TABLE proceso.TMD_GRUPO_NO_RECUPERABLE_PERSONA(
        ideGrupoNoRecuperablePersona bigint IDENTITY(1,1) NOT NULL,
        ideGrupoNoRecuperable bigint NOT NULL,
        -- Repetidos del grupo para que el indice unico impida tener a una
        -- persona en dos grupos del mismo periodo, aun con dos guardados a la vez.
        numAnio int NOT NULL,
        numMes int NOT NULL,
        idePersona int NOT NULL,
        txtNombreCompleto varchar(250) NULL,
        Documento varchar(30) NULL,
        Area varchar(200) NULL,
        Departamento varchar(200) NULL,
        Cargo varchar(200) NULL,
        flgEstado int NOT NULL CONSTRAINT DF_TMD_GRUPO_NO_RECUPERABLE_PERSONA_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMD_GRUPO_NO_RECUPERABLE_PERSONA_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMD_GRUPO_NO_RECUPERABLE_PERSONA PRIMARY KEY CLUSTERED (ideGrupoNoRecuperablePersona ASC),
        CONSTRAINT FK_TMD_GRUPO_NO_RECUPERABLE_PERSONA_GRUPO FOREIGN KEY (ideGrupoNoRecuperable)
            REFERENCES proceso.TMC_GRUPO_NO_RECUPERABLE (ideGrupoNoRecuperable)
    );

    CREATE NONCLUSTERED INDEX IX_TMD_GRUPO_NO_RECUPERABLE_PERSONA_GRUPO
        ON proceso.TMD_GRUPO_NO_RECUPERABLE_PERSONA (ideGrupoNoRecuperable, flgEstado);

    CREATE UNIQUE NONCLUSTERED INDEX UX_TMD_GRUPO_NO_RECUPERABLE_PERSONA_PERIODO
        ON proceso.TMD_GRUPO_NO_RECUPERABLE_PERSONA (numAnio, numMes, idePersona) WHERE flgEstado = 1;
END
GO

IF TYPE_ID('proceso.TYPE_GRUPO_NO_RECUPERABLE_PERSONA') IS NULL
    CREATE TYPE proceso.TYPE_GRUPO_NO_RECUPERABLE_PERSONA AS TABLE (
        idePersona int NOT NULL PRIMARY KEY,
        txtNombreCompleto varchar(250) NULL,
        Documento varchar(30) NULL,
        Area varchar(200) NULL,
        Departamento varchar(200) NULL,
        Cargo varchar(200) NULL
    );
GO

/* -------------------------------------------------------------------------
   2. Busqueda de personal del periodo en BD_SPRING

   Es la consulta del lider, con el periodo como parametro, el filtro por
   nombre, cargo, area o departamento, y solo empleados. Se limita a 100 filas: es un buscador,
   no un listado.
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_PersonalSpring_Buscar
    @numAnio     int,
    @numMes      int,
    @txtCriterio varchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID('BD_SPRING') IS NULL
        THROW 50075, 'La base de datos BD_SPRING no esta disponible en este servidor.', 1;

    DECLARE @periodo varchar(10) = CONCAT(@numAnio, RIGHT('0' + CAST(@numMes AS varchar(2)), 2));
    DECLARE @patron varchar(102) = CONCAT('%', NULLIF(TRIM(@txtCriterio), ''), '%');

    EXEC sp_executesql N'
        SELECT TOP (100) *
        FROM (
            SELECT DISTINCT
                pm.Persona AS idePersona,
                TRIM(pm.NombreCompleto) AS txtNombreCompleto,
                TRIM(pm.Documento) AS Documento,
                TRIM(hrdiv.DescripcionLarga) AS Area,
                TRIM(hrdep.Descripcion) AS Departamento,
                TRIM(hre.Descripcion) AS Cargo
            FROM BD_SPRING.dbo.voucherdetail AS vd
            INNER JOIN BD_SPRING.dbo.voucherheader AS vh ON vh.period = vd.period AND vh.voucherno = vd.voucherno
            LEFT JOIN BD_SPRING.dbo.accountmst AS am ON am.account = vd.Account
            LEFT JOIN BD_SPRING.dbo.PersonaMast AS pm ON pm.Persona = vd.vendor
            LEFT JOIN BD_SPRING.dbo.EmpleadoMast AS em ON em.Empleado = pm.Persona
            LEFT JOIN BD_SPRING.dbo.HR_PuestoEmpresa AS hre ON hre.CodigoPuesto = em.CodigoCargo
            LEFT JOIN BD_SPRING.dbo.HR_Departamento AS hrdep ON hrdep.Departamento = em.DepartamentoOperacional
            LEFT JOIN BD_SPRING.dbo.HR_Division AS hrdiv ON hrdiv.Division = em.Division
            WHERE vd.period = @periodo
              -- Solo empleados: la consulta original tambien trae proveedores
              -- (bancos, por ejemplo), y su gasto se reparte como OTROS, no por persona.
              AND em.Empleado IS NOT NULL
        ) p
        WHERE @patron = ''%%''
           OR p.txtNombreCompleto LIKE @patron
           OR p.Cargo LIKE @patron
           OR p.Area LIKE @patron
           OR p.Departamento LIKE @patron
        ORDER BY p.txtNombreCompleto;',
        N'@periodo varchar(10), @patron varchar(102)',
        @periodo = @periodo, @patron = @patron;
END
GO

/* -------------------------------------------------------------------------
   3. Grupos del periodo
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_GrupoNoRecuperable_Listar
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT g.ideGrupoNoRecuperable, g.numAnio, g.numMes, g.nomGrupo,
           (SELECT COUNT(*) FROM proceso.TMD_GRUPO_NO_RECUPERABLE_PERSONA p
            WHERE p.ideGrupoNoRecuperable = g.ideGrupoNoRecuperable AND p.flgEstado = 1) AS numPersonas
    FROM proceso.TMC_GRUPO_NO_RECUPERABLE g
    WHERE g.numAnio = @numAnio AND g.numMes = @numMes AND g.flgEstado = 1
    ORDER BY g.nomGrupo;
END
GO

/* Cabecera y luego el personal, en dos conjuntos de resultados. */
CREATE OR ALTER PROCEDURE proceso.usp_GrupoNoRecuperable_Obtener
    @ideGrupoNoRecuperable bigint
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM proceso.TMC_GRUPO_NO_RECUPERABLE
                   WHERE ideGrupoNoRecuperable = @ideGrupoNoRecuperable AND flgEstado = 1)
        THROW 50073, 'El grupo indicado no existe o fue eliminado.', 1;

    SELECT g.ideGrupoNoRecuperable, g.numAnio, g.numMes, g.nomGrupo,
           (SELECT COUNT(*) FROM proceso.TMD_GRUPO_NO_RECUPERABLE_PERSONA p
            WHERE p.ideGrupoNoRecuperable = g.ideGrupoNoRecuperable AND p.flgEstado = 1) AS numPersonas
    FROM proceso.TMC_GRUPO_NO_RECUPERABLE g
    WHERE g.ideGrupoNoRecuperable = @ideGrupoNoRecuperable;

    SELECT p.idePersona, p.txtNombreCompleto, p.Documento, p.Area, p.Departamento, p.Cargo
    FROM proceso.TMD_GRUPO_NO_RECUPERABLE_PERSONA p
    WHERE p.ideGrupoNoRecuperable = @ideGrupoNoRecuperable AND p.flgEstado = 1
    ORDER BY p.txtNombreCompleto;
END
GO

/*
   Alta y edicion comparten las reglas, asi que van en un solo procedimiento:
   con @ideGrupoNoRecuperable nulo da de alta; con valor, reemplaza nombre y
   personal. Devuelve el id del grupo.
*/
CREATE OR ALTER PROCEDURE proceso.usp_GrupoNoRecuperable_Guardar
    @ideGrupoNoRecuperable bigint = NULL,
    @numAnio    int,
    @numMes     int,
    @nomGrupo   varchar(100),
    @personas   proceso.TYPE_GRUPO_NO_RECUPERABLE_PERSONA READONLY,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @nomGrupo = UPPER(TRIM(@nomGrupo));

    IF @ideGrupoNoRecuperable IS NOT NULL
    BEGIN
        -- En la edicion el periodo es el del grupo, no el que mande el cliente.
        SELECT @numAnio = numAnio, @numMes = numMes
        FROM proceso.TMC_GRUPO_NO_RECUPERABLE
        WHERE ideGrupoNoRecuperable = @ideGrupoNoRecuperable AND flgEstado = 1;

        IF @@ROWCOUNT = 0
            THROW 50073, 'El grupo indicado no existe o fue eliminado.', 1;
    END

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50070, 'El periodo esta cerrado: sus grupos de gasto no recuperable no se pueden modificar.', 1;

    -- El nombre es el encabezado de una columna del reporte: no puede repetir
    -- los fijos, y solo lleva letras, numeros, espacios, punto, guion y
    -- parentesis. El reporte usa nombres con guion bajo para sus columnas internas.
    IF ISNULL(@nomGrupo, '') = '' OR @nomGrupo IN ('GERENCIA', 'MONTO', 'TOTAL')
        THROW 50074, 'El nombre del grupo es obligatorio y no puede ser GERENCIA, MONTO ni TOTAL.', 1;

    -- Vocales con tilde, dieresis y enie por codigo, para no depender de la
    -- codificacion del archivo. El guion va al final: dentro de [] es literal.
    DECLARE @permitidos varchar(40) = '%[^A-Z0-9 .()'
        + CHAR(193) + CHAR(201) + CHAR(205) + CHAR(211) + CHAR(218) + CHAR(220) + CHAR(209) + '-]%';

    IF @nomGrupo COLLATE Latin1_General_BIN LIKE @permitidos
        THROW 50074, 'El nombre del grupo solo admite letras, numeros, espacios, punto, guion y parentesis.', 1;

    IF NOT EXISTS (SELECT 1 FROM @personas)
        THROW 50074, 'El grupo debe tener al menos una persona.', 1;

    IF EXISTS (SELECT 1 FROM proceso.TMC_GRUPO_NO_RECUPERABLE
               WHERE numAnio = @numAnio AND numMes = @numMes AND nomGrupo = @nomGrupo
                 AND flgEstado = 1
                 AND ideGrupoNoRecuperable <> ISNULL(@ideGrupoNoRecuperable, 0))
        THROW 50071, 'Ya existe un grupo con ese nombre en el periodo.', 1;

    -- Una persona en dos grupos se restaria dos veces del gasto recuperable.
    DECLARE @repetida varchar(400) =
        (SELECT TOP (1) CONCAT(ISNULL(p.txtNombreCompleto, CAST(p.idePersona AS varchar(20))), ' ya esta en el grupo ', g.nomGrupo, '.')
         FROM @personas p
         JOIN proceso.TMD_GRUPO_NO_RECUPERABLE_PERSONA gp
           ON gp.idePersona = p.idePersona AND gp.flgEstado = 1
         JOIN proceso.TMC_GRUPO_NO_RECUPERABLE g
           ON g.ideGrupoNoRecuperable = gp.ideGrupoNoRecuperable AND g.flgEstado = 1
         WHERE g.numAnio = @numAnio AND g.numMes = @numMes
           AND g.ideGrupoNoRecuperable <> ISNULL(@ideGrupoNoRecuperable, 0));

    IF @repetida IS NOT NULL
        THROW 50072, @repetida, 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @ideGrupoNoRecuperable IS NULL
        BEGIN
            INSERT INTO proceso.TMC_GRUPO_NO_RECUPERABLE (numAnio, numMes, nomGrupo, flgEstado, txtUsuarioCreacion)
            VALUES (@numAnio, @numMes, @nomGrupo, 1, @txtUsuario);
            SET @ideGrupoNoRecuperable = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE proceso.TMC_GRUPO_NO_RECUPERABLE
            SET nomGrupo = @nomGrupo,
                fecActualizacion = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideGrupoNoRecuperable = @ideGrupoNoRecuperable;

            UPDATE proceso.TMD_GRUPO_NO_RECUPERABLE_PERSONA
            SET flgEstado = 0,
                fecActualizacion = GETDATE(),
                txtUsuarioActualizacion = @txtUsuario
            WHERE ideGrupoNoRecuperable = @ideGrupoNoRecuperable AND flgEstado = 1;
        END

        INSERT INTO proceso.TMD_GRUPO_NO_RECUPERABLE_PERSONA
              (ideGrupoNoRecuperable, numAnio, numMes, idePersona, txtNombreCompleto, Documento, Area,
               Departamento, Cargo, flgEstado, txtUsuarioCreacion)
        SELECT @ideGrupoNoRecuperable, @numAnio, @numMes, p.idePersona, p.txtNombreCompleto, p.Documento, p.Area,
               p.Departamento, p.Cargo, 1, @txtUsuario
        FROM @personas p;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @ideGrupoNoRecuperable AS ideGrupoNoRecuperable;
END
GO

CREATE OR ALTER PROCEDURE proceso.usp_GrupoNoRecuperable_Eliminar
    @ideGrupoNoRecuperable bigint,
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @numAnio int, @numMes int;

    SELECT @numAnio = numAnio, @numMes = numMes
    FROM proceso.TMC_GRUPO_NO_RECUPERABLE
    WHERE ideGrupoNoRecuperable = @ideGrupoNoRecuperable AND flgEstado = 1;

    IF @numAnio IS NULL
        THROW 50073, 'El grupo indicado no existe o fue eliminado.', 1;

    IF EXISTS (SELECT 1 FROM registro.TMC_PERIODO
               WHERE numAnio = @numAnio AND numMes = @numMes AND flgEstado = 2)
        THROW 50070, 'El periodo esta cerrado: sus grupos de gasto no recuperable no se pueden modificar.', 1;

    BEGIN TRANSACTION;

    UPDATE proceso.TMD_GRUPO_NO_RECUPERABLE_PERSONA
    SET flgEstado = 0, fecActualizacion = GETDATE(), txtUsuarioActualizacion = @txtUsuario
    WHERE ideGrupoNoRecuperable = @ideGrupoNoRecuperable AND flgEstado = 1;

    UPDATE proceso.TMC_GRUPO_NO_RECUPERABLE
    SET flgEstado = 0, fecActualizacion = GETDATE(), txtUsuarioActualizacion = @txtUsuario
    WHERE ideGrupoNoRecuperable = @ideGrupoNoRecuperable;

    COMMIT TRANSACTION;
END
GO

/* -------------------------------------------------------------------------
   4. Opcion de menu, solo para el perfil Contador

   Igual que el script 28: idempotente y sin filtrar por flgEstado, para no
   devolver la opcion a un perfil al que el administrador se la quito.
   ------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
SELECT 'GASTO_NO_RECUPERABLE', 'Gasto no recuperable', '/costo-labor/gasto-no-recuperable',
       'bi bi-person-x', p.ideOpcion, 5, 1, @usuario
FROM seguridad.TG_OPCION p
WHERE p.codOpcion = 'COSTO_LABOR'
  AND NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'GASTO_NO_RECUPERABLE');
GO

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('CONTADOR', 'COSTO_LABOR'), ('CONTADOR', 'GASTO_NO_RECUPERABLE')) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
