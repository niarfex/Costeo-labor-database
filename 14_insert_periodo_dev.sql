/* =========================================================================
   HU-005 - Datos de prueba para desarrollo local

   SOLO PARA DESARROLLO. No ejecutar en Calidad ni en Produccion.

   En el sistema real, el periodo y la asignacion de proyectos por trabajador
   provienen del ERP SPRING; hoy ninguna HU se hace cargo de poblarlas, asi
   que sin esta semilla la grilla de la HU-005 no tiene filas que mostrar.

   Los nombres y codigos reproducen los del mockup v2 para que la pantalla
   se vea igual que el diseno. El script es idempotente.
   ========================================================================= */

USE [COSTO_LABOR];
GO

/* Obligatorio: las tablas con indices filtrados rechazan cualquier DML y
   cualquier procedimiento compilado sin estas opciones. SQL Server las
   guarda al crear el objeto, asi que si el despliegue se hace con una
   herramienta que no las active, el procedimiento se crea bien pero
   falla al ejecutarse. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

DECLARE @usuario varchar(30) = 'SEED_DEV';
DECLARE @anio    int = 2026;
DECLARE @mes     int = 8;

/* ---------------------------------------------------------------------------
   1. Periodo activo (flgEstado: 1 = Activo, 2 = Cerrado)
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM registro.TMC_PERIODO WHERE numAnio = @anio AND numMes = @mes)
    INSERT INTO registro.TMC_PERIODO (numAnio, numMes, flgEstado, txtUsuarioCreacion)
    VALUES (@anio, @mes, 1, @usuario);

DECLARE @idePeriodo bigint =
    (SELECT idePeriodo FROM registro.TMC_PERIODO WHERE numAnio = @anio AND numMes = @mes);
GO

/* ---------------------------------------------------------------------------
   2. Parametrizacion del periodo (HU-004)

   Se habilitan actividades, tareas y observaciones para poder probar la
   variante mas completa del modal de captura del CA-03.
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM registro.TMC_PARAMETRO
               WHERE numAnio = 2026 AND numMes = 8 AND flgEstado = 1)
    INSERT INTO registro.TMC_PARAMETRO
          (numAnio, numMes, flgRegActividad, flgRegTareaxActividad, flgRegComentarioxActividad,
           flgRegObservacionxTarea, flgRegObservacionxProyecto, flgRegObservacionxPeriodo,
           flgRegOtrosAtributos, flgEstado, txtUsuarioCreacion)
    VALUES (2026, 8, 1, 1, 1, 1, 1, 1, 0, 1, 'SEED_DEV');
GO

/* ---------------------------------------------------------------------------
   3. Trabajadores y su vinculo con el usuario de Entra ID

   El UPDATE de ideEmpleado depende de 13_alter_usuario_empleado.sql; si esa
   propuesta no se aplico, se omite sin romper el resto de la semilla.
   --------------------------------------------------------------------------- */
DECLARE @empleados TABLE (ideEmpleado bigint, nomEmpleado varchar(200), txtUsuario varchar(100), codPerfil varchar(30));
INSERT INTO @empleados VALUES
 (1001, 'Juan Perez Perez',     'juan.perez@amsac.pe',   'TRABAJADOR'),
 (1002, 'Cesar Chavez Chavez',  'cesar.chavez@amsac.pe', 'TRABAJADOR'),
 (1003, 'Ana Rosales Jimenez',  'ana.rosales@amsac.pe',  'TRABAJADOR'),
 (2001, 'Luis Lopez Lopez',     'luis.lopez@amsac.pe',   'JEFE');

INSERT INTO seguridad.TMD_PERFIL_USUARIO (idePerfil, txtUsuario, txtNombreCompleto, flgEstado, txtUsuarioCreacion)
SELECT p.idePerfil, e.txtUsuario, e.nomEmpleado, 1, 'SEED_DEV'
FROM @empleados e
JOIN seguridad.TMC_PERFIL p ON p.codPerfil = e.codPerfil
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_USUARIO u WHERE u.txtUsuario = e.txtUsuario);

IF COL_LENGTH('seguridad.TMD_PERFIL_USUARIO', 'ideEmpleado') IS NOT NULL
    EXEC sp_executesql N'
        UPDATE u SET u.ideEmpleado = e.ideEmpleado
        FROM seguridad.TMD_PERFIL_USUARIO u
        JOIN (VALUES (1001, ''juan.perez@amsac.pe''),
                     (1002, ''cesar.chavez@amsac.pe''),
                     (1003, ''ana.rosales@amsac.pe''),
                     (2001, ''luis.lopez@amsac.pe''))
             AS e(ideEmpleado, txtUsuario) ON e.txtUsuario = u.txtUsuario
        WHERE u.ideEmpleado IS NULL;';
GO

/* ---------------------------------------------------------------------------
   4. Observacion por periodo de cada trabajador (CA-01)
   --------------------------------------------------------------------------- */
DECLARE @idePeriodo bigint =
    (SELECT idePeriodo FROM registro.TMC_PERIODO WHERE numAnio = 2026 AND numMes = 8);

INSERT INTO registro.TMD_PERIODO_EMPLEADO (idePeriodo, numAnio, numMes, ideEmpleado, nomEmpleado, flgEstado, txtUsuarioCreacion)
SELECT @idePeriodo, 2026, 8, e.ideEmpleado, e.nomEmpleado, 1, 'SEED_DEV'
FROM (VALUES (1001, 'Juan Perez Perez'),
             (1002, 'Cesar Chavez Chavez'),
             (1003, 'Ana Rosales Jimenez')) AS e(ideEmpleado, nomEmpleado)
WHERE NOT EXISTS (SELECT 1 FROM registro.TMD_PERIODO_EMPLEADO pe
                  WHERE pe.numAnio = 2026 AND pe.numMes = 8 AND pe.ideEmpleado = e.ideEmpleado);

/* ---------------------------------------------------------------------------
   5. Proyectos asignados a cada trabajador: son las filas de la grilla
   --------------------------------------------------------------------------- */
INSERT INTO registro.TMD_PERIODO_PROYECTO
      (idePeriodo, numAnio, numMes, codProyecto, nomProyecto, ideEmpleado, nomEmpleado, flgEstado, txtUsuarioCreacion)
SELECT @idePeriodo, 2026, 8, a.codProyecto, a.nomProyecto, a.ideEmpleado, a.nomEmpleado, 1, 'SEED_DEV'
FROM (VALUES
      ('000009', 'MICHIQUILLAY',      1001, 'Juan Perez Perez'),
      ('000040', 'MARGEN IZQUIERDA',  1001, 'Juan Perez Perez'),
      ('210035', 'MARCAVALLE',        1001, 'Juan Perez Perez'),
      ('000009', 'MICHIQUILLAY',      1002, 'Cesar Chavez Chavez'),
      ('000040', 'MARGEN IZQUIERDA',  1002, 'Cesar Chavez Chavez'),
      ('210035', 'MARCAVALLE',        1003, 'Ana Rosales Jimenez')
     ) AS a(codProyecto, nomProyecto, ideEmpleado, nomEmpleado)
WHERE NOT EXISTS (SELECT 1 FROM registro.TMD_PERIODO_PROYECTO pp
                  WHERE pp.numAnio = 2026 AND pp.numMes = 8
                    AND pp.ideEmpleado = a.ideEmpleado AND pp.codProyecto = a.codProyecto);
GO
