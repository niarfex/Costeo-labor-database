/* =========================================================================
   HU-006 - Datos de prueba para desarrollo local

   SOLO PARA DESARROLLO. No ejecutar en Calidad ni en Produccion.

   Reproduce la estructura del prototipo: dos departamentos (DGO y DIP), cada
   uno con un JEFE, un ADMINISTRATIVO y dos SUBORDINADO. El CA-01 abre la
   vista en el mes anterior al actual, por eso la semilla carga ese periodo y
   no el corriente.

   Idempotente. Los guardas comparan por la misma llave que tienen las
   constraints unicas, no por flgEstado: una fila desactivada igual ocupa la
   combinacion y haria fallar el INSERT.
   ========================================================================= */

USE [COSTO_LABOR];
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---------------------------------------------------------------------------
   Periodo del mes anterior (flgEstado: 1 = Activo, 2 = Cerrado)
   --------------------------------------------------------------------------- */
DECLARE @mesAnterior date = DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
DECLARE @anio int = YEAR(@mesAnterior);
DECLARE @mes  int = MONTH(@mesAnterior);

IF NOT EXISTS (SELECT 1 FROM registro.TMC_PERIODO WHERE numAnio = @anio AND numMes = @mes)
    INSERT INTO registro.TMC_PERIODO (numAnio, numMes, flgEstado, txtUsuarioCreacion)
    VALUES (@anio, @mes, 1, 'SEED_DEV');
ELSE
    UPDATE registro.TMC_PERIODO SET flgEstado = 1
    WHERE numAnio = @anio AND numMes = @mes AND flgEstado <> 1;

/* ---------------------------------------------------------------------------
   Parametrizacion del periodo (HU-004)

   Se habilitan actividades, tareas y observaciones para poder probar la
   variante mas completa del modal de captura del CA-03.
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM registro.TMC_PARAMETRO WHERE numAnio = @anio AND numMes = @mes)
    INSERT INTO registro.TMC_PARAMETRO
          (numAnio, numMes, flgRegActividad, flgRegTareaxActividad, flgRegComentarioxActividad,
           flgRegObservacionxTarea, flgRegObservacionxProyecto, flgRegObservacionxPeriodo,
           flgRegOtrosAtributos, flgEstado, txtUsuarioCreacion)
    VALUES (@anio, @mes, 1, 1, 1, 1, 1, 1, 0, 1, 'SEED_DEV');
ELSE
    UPDATE registro.TMC_PARAMETRO
    SET flgRegActividad = 1, flgRegTareaxActividad = 1, flgRegComentarioxActividad = 1,
        flgRegObservacionxTarea = 1, flgRegObservacionxProyecto = 1,
        flgRegObservacionxPeriodo = 1, flgEstado = 1
    WHERE numAnio = @anio AND numMes = @mes;
GO

/* ---------------------------------------------------------------------------
   Trabajadores del prototipo y su vinculo con el usuario de Entra ID
   --------------------------------------------------------------------------- */
DECLARE @personas TABLE (
    ideEmpleado bigint, nomEmpleado varchar(200), txtUsuario varchar(100),
    codPerfil varchar(30), codDepartamento varchar(10), nomDepartamento varchar(200),
    codNivel varchar(20), ideEmpleadoJefe bigint);

INSERT INTO @personas VALUES
 (2001, 'Luis Lopez Lopez',        'luis.lopez@amsac.pe',      'JEFE',       'DGO', 'Direccion de Gestion de Obras',   'JEFE',           NULL),
 (1001, 'Juan Perez Perez',        'juan.perez@amsac.pe',      'TRABAJADOR', 'DGO', 'Direccion de Gestion de Obras',   'ADMINISTRATIVO', 2001),
 (1002, 'Cesar Chavez Chavez',     'cesar.chavez@amsac.pe',    'TRABAJADOR', 'DGO', 'Direccion de Gestion de Obras',   'SUBORDINADO',    2001),
 (1003, 'Ana Rosales Jimenez',     'ana.rosales@amsac.pe',     'TRABAJADOR', 'DGO', 'Direccion de Gestion de Obras',   'SUBORDINADO',    2001),
 (2002, 'Luis Sanchez Sanchez',    'luis.sanchez@amsac.pe',    'JEFE',       'DIP', 'Direccion de Inversion Privada',  'JEFE',           NULL),
 (1004, 'Juan Portilla Sandoval',  'juan.portilla@amsac.pe',   'TRABAJADOR', 'DIP', 'Direccion de Inversion Privada',  'ADMINISTRATIVO', 2002),
 (1005, 'Cesar Guzman Torres',     'cesar.guzman@amsac.pe',    'TRABAJADOR', 'DIP', 'Direccion de Inversion Privada',  'SUBORDINADO',    2002),
 (1006, 'Ana Gutierrez Gutierrez', 'ana.gutierrez@amsac.pe',   'TRABAJADOR', 'DIP', 'Direccion de Inversion Privada',  'SUBORDINADO',    2002);

INSERT INTO seguridad.TMD_PERFIL_USUARIO (idePerfil, txtUsuario, txtNombreCompleto, flgEstado, txtUsuarioCreacion)
SELECT p.idePerfil, e.txtUsuario, e.nomEmpleado, 1, 'SEED_DEV'
FROM @personas e
JOIN seguridad.TMC_PERFIL p ON p.codPerfil = e.codPerfil
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_USUARIO u WHERE u.txtUsuario = e.txtUsuario);

UPDATE u SET u.ideEmpleado = e.ideEmpleado
FROM seguridad.TMD_PERFIL_USUARIO u
JOIN @personas e ON e.txtUsuario = u.txtUsuario
WHERE u.ideEmpleado IS NULL;

/* ---------------------------------------------------------------------------
   Empleados del periodo, con departamento, nivel y jefatura (CA-02)
   --------------------------------------------------------------------------- */
DECLARE @mesAnterior date = DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
DECLARE @anio int = YEAR(@mesAnterior);
DECLARE @mes  int = MONTH(@mesAnterior);
DECLARE @idePeriodo bigint =
    (SELECT idePeriodo FROM registro.TMC_PERIODO WHERE numAnio = @anio AND numMes = @mes);

INSERT INTO registro.TMD_PERIODO_EMPLEADO
      (idePeriodo, numAnio, numMes, ideEmpleado, nomEmpleado,
       codDepartamento, nomDepartamento, codNivel, ideEmpleadoJefe, flgEstado, txtUsuarioCreacion)
SELECT @idePeriodo, @anio, @mes, e.ideEmpleado, e.nomEmpleado,
       e.codDepartamento, e.nomDepartamento, e.codNivel, e.ideEmpleadoJefe, 1, 'SEED_DEV'
FROM @personas e
WHERE NOT EXISTS (SELECT 1 FROM registro.TMD_PERIODO_EMPLEADO pe
                  WHERE pe.numAnio = @anio AND pe.numMes = @mes AND pe.ideEmpleado = e.ideEmpleado);

-- Los periodos que ya existian de la HU-005 no traen la unidad organica
UPDATE pe
SET pe.codDepartamento = e.codDepartamento,
    pe.nomDepartamento = e.nomDepartamento,
    pe.codNivel        = e.codNivel,
    pe.ideEmpleadoJefe = e.ideEmpleadoJefe
FROM registro.TMD_PERIODO_EMPLEADO pe
JOIN @personas e ON e.ideEmpleado = pe.ideEmpleado
WHERE pe.codNivel IS NULL;

/* ---------------------------------------------------------------------------
   Proyectos asignados: son las columnas de la grilla mensual
   --------------------------------------------------------------------------- */
DECLARE @asignaciones TABLE (codProyecto varchar(30), nomProyecto varchar(200), ideEmpleado bigint);
INSERT INTO @asignaciones VALUES
 ('000009', 'MICHIQUILLAY',     1002), ('000040', 'MARGEN IZQUIERDA', 1002),
 ('210035', 'MARCAVALLE',       1002), ('000108', 'AZALIA Y PUCA',    1002),
 ('000009', 'MICHIQUILLAY',     1003), ('210035', 'MARCAVALLE',       1003),
 ('000040', 'MARGEN IZQUIERDA', 1005), ('000108', 'AZALIA Y PUCA',    1005),
 ('210035', 'MARCAVALLE',       1006), ('000009', 'MICHIQUILLAY',     1006);

INSERT INTO registro.TMD_PERIODO_PROYECTO
      (idePeriodo, numAnio, numMes, codProyecto, nomProyecto, ideEmpleado, nomEmpleado,
       flgEstado, txtUsuarioCreacion)
SELECT @idePeriodo, @anio, @mes, a.codProyecto, a.nomProyecto, a.ideEmpleado, p.nomEmpleado,
       1, 'SEED_DEV'
FROM @asignaciones a
JOIN @personas p ON p.ideEmpleado = a.ideEmpleado
WHERE NOT EXISTS (SELECT 1 FROM registro.TMD_PERIODO_PROYECTO pp
                  WHERE pp.numAnio = @anio AND pp.numMes = @mes
                    AND pp.ideEmpleado = a.ideEmpleado AND pp.codProyecto = a.codProyecto);
GO
