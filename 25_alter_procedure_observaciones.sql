/* =========================================================================
   25 - Observaciones y mejoras del 13/09/2026

   Multiperfil
     usp_Perfil_ListarPorUsuario  devuelve tambien el nombre del perfil y en
                                  orden de asignacion, para el selector de
                                  perfil y para elegir el perfil inicial.
     usp_Opcion_ListarPorUsuario  acepta @codPerfil: el menu muestra solo las
                                  opciones del perfil activo.

   Combo de trabajadores
     usp_RegistroHoraDia_ListarTrabajadores  acepta @ideEmpleadoJefe: la
                                  jefatura ve solo a su personal a cargo.
     usp_RegistroHoraMes_ListarTrabajadores,
     usp_RegistroHoraMes_ListarProyectos,
     usp_RegistroHoraMes_ListarHoras          aceptan @ideEmpleado: el perfil
                                  Trabajador ve solo su propia fila.

   Campos de observacion
     usp_RegistroHoraMes_ListarDesglose  devuelve tambien el comentario por
                                  actividad, para que la jefatura lo vea en
                                  el modal «Horas registradas».

   Todos los parametros nuevos son opcionales y con NULL se comportan como
   antes, asi que el backend anterior sigue funcionando con este script.
   ========================================================================= */

USE [COSTO_LABOR];
GO

/* Obligatorio: las tablas con indices filtrados rechazan cualquier DML y
   cualquier procedimiento compilado sin estas opciones. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* -------------------------------------------------------------------------
   Multiperfil
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE seguridad.usp_Perfil_ListarPorUsuario
    @txtUsuario varchar(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.codPerfil,
           p.nomPerfil
    FROM seguridad.TMD_PERFIL_USUARIO pu
    INNER JOIN seguridad.TMC_PERFIL p ON p.idePerfil = pu.idePerfil AND p.flgEstado = 1
    WHERE pu.txtUsuario = @txtUsuario
      AND pu.flgEstado = 1
    -- El primer perfil asignado es el que queda activo al ingresar.
    ORDER BY pu.idePerfilUsuario;
END
GO

CREATE OR ALTER PROCEDURE seguridad.usp_Opcion_ListarPorUsuario
    @txtUsuario varchar(100),
    @codPerfil  varchar(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
            o.ideOpcion, o.codOpcion, o.nomOpcion, o.txtRuta, o.txtIcono,
            o.ideOpcionPadre, o.numOrden
    FROM seguridad.TMD_PERFIL_USUARIO pu
    INNER JOIN seguridad.TMC_PERFIL        p  ON p.idePerfil  = pu.idePerfil AND p.flgEstado  = 1
    INNER JOIN seguridad.TMD_PERFIL_OPCION po ON po.idePerfil = p.idePerfil  AND po.flgEstado = 1
    INNER JOIN seguridad.TG_OPCION         o  ON o.ideOpcion  = po.ideOpcion AND o.flgEstado  = 1
    WHERE pu.txtUsuario = @txtUsuario
      AND pu.flgEstado = 1
      AND (@codPerfil IS NULL OR p.codPerfil = @codPerfil)
    ORDER BY o.ideOpcionPadre, o.numOrden;
END
GO

/* -------------------------------------------------------------------------
   HU-005: combo de trabajadores acotado a la jefatura
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraDia_ListarTrabajadores
    @numAnio         int,
    @numMes          int,
    @ideEmpleadoJefe bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  pe.ideEmpleado,
            pe.nomEmpleado,
            pe.txtObservaciones,
            SUM(ISNULL(r.numHoras, 0)) AS numHorasTotal,
            SUM(CASE WHEN e.codEstadoValidacion = 'PENDIENTE' THEN 1 ELSE 0 END) AS numDiasPendientes
    FROM registro.TMD_PERIODO_EMPLEADO pe
    LEFT JOIN registro.TMD_REGISTRO_HORADIA r
           ON r.ideEmpleado = pe.ideEmpleado AND r.numAnio = pe.numAnio
          AND r.numMes = pe.numMes AND r.flgEstado = 1
    LEFT JOIN registro.VW_REGISTRO_HORADIA_ESTADO e
           ON e.ideEmpleado = r.ideEmpleado AND e.fecLabor = r.fecLabor
    WHERE pe.numAnio = @numAnio
      AND pe.numMes  = @numMes
      AND pe.flgEstado = 1
      -- Mismo criterio que la HU-006: la jefatura se ve a si misma y a su equipo.
      AND (@ideEmpleadoJefe IS NULL
           OR pe.ideEmpleadoJefe = @ideEmpleadoJefe
           OR pe.ideEmpleado = @ideEmpleadoJefe)
    GROUP BY pe.ideEmpleado, pe.nomEmpleado, pe.txtObservaciones
    ORDER BY pe.nomEmpleado;
END
GO

/* -------------------------------------------------------------------------
   HU-006: el perfil Trabajador ve solo su fila
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarTrabajadores
    @numAnio         int,
    @numMes          int,
    @ideEmpleadoJefe bigint = NULL,
    @ideEmpleado     bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  pe.ideEmpleado,
            pe.nomEmpleado,
            pe.codDepartamento,
            pe.nomDepartamento,
            pe.codNivel,
            pe.txtObservaciones,
            e.codEstadoValidacion
    FROM registro.TMD_PERIODO_EMPLEADO pe
    LEFT JOIN registro.VW_REGISTRO_HORAMES_ESTADO e
           ON e.ideEmpleado = pe.ideEmpleado
          AND e.numAnio = pe.numAnio
          AND e.numMes  = pe.numMes
    WHERE pe.numAnio = @numAnio
      AND pe.numMes  = @numMes
      AND pe.flgEstado = 1
      -- La jefatura tambien se ve a si misma: el prototipo la muestra como
      -- primera fila de su departamento, aunque no dependa de nadie.
      AND (@ideEmpleadoJefe IS NULL
           OR pe.ideEmpleadoJefe = @ideEmpleadoJefe
           OR pe.ideEmpleado = @ideEmpleadoJefe)
      AND (@ideEmpleado IS NULL OR pe.ideEmpleado = @ideEmpleado)
    ORDER BY pe.codDepartamento,
             CASE pe.codNivel WHEN 'JEFE' THEN 1 WHEN 'ADMINISTRATIVO' THEN 2 ELSE 3 END,
             pe.nomEmpleado;
END
GO

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarProyectos
    @numAnio         int,
    @numMes          int,
    @ideEmpleadoJefe bigint = NULL,
    @ideEmpleado     bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
           pp.codProyecto,
           pp.nomProyecto
    FROM registro.TMD_PERIODO_PROYECTO pp
    JOIN registro.TMD_PERIODO_EMPLEADO pe
      ON pe.ideEmpleado = pp.ideEmpleado
     AND pe.numAnio = pp.numAnio
     AND pe.numMes  = pp.numMes
     AND pe.flgEstado = 1
    WHERE pp.numAnio = @numAnio
      AND pp.numMes  = @numMes
      AND pp.flgEstado = 1
      AND (@ideEmpleadoJefe IS NULL
           OR pe.ideEmpleadoJefe = @ideEmpleadoJefe
           OR pe.ideEmpleado = @ideEmpleadoJefe)
      AND (@ideEmpleado IS NULL OR pe.ideEmpleado = @ideEmpleado)
    ORDER BY pp.codProyecto;
END
GO

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarHoras
    @numAnio         int,
    @numMes          int,
    @ideEmpleadoJefe bigint = NULL,
    @ideEmpleado     bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  r.ideRegistroHorames,
            r.ideEmpleado,
            r.codProyecto,
            r.numHoras
    FROM registro.TMD_REGISTRO_HORAMES r
    JOIN registro.TMD_PERIODO_EMPLEADO pe
      ON pe.ideEmpleado = r.ideEmpleado
     AND pe.numAnio = r.numAnio
     AND pe.numMes  = r.numMes
     AND pe.flgEstado = 1
    WHERE r.numAnio = @numAnio
      AND r.numMes  = @numMes
      AND r.flgEstado = 1
      AND (@ideEmpleadoJefe IS NULL
           OR pe.ideEmpleadoJefe = @ideEmpleadoJefe
           OR pe.ideEmpleado = @ideEmpleadoJefe)
      AND (@ideEmpleado IS NULL OR pe.ideEmpleado = @ideEmpleado)
    ORDER BY r.ideEmpleado, r.codProyecto;
END
GO

/* -------------------------------------------------------------------------
   HU-006: el modal «Horas registradas» muestra el comentario por actividad
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraMes_ListarDesglose
    @ideEmpleado bigint,
    @numAnio     int,
    @numMes      int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  r.ideRegistroHorames,
            r.codProyecto,
            r.nomProyecto,
            r.numHoras AS numHorasProyecto,
            r.txtObservaciones,
            a.txtActividad,
            a.txtComentarios AS txtComentarioActividad,
            t.txtTarea,
            ISNULL(t.txtObservaciones, a.txtObservaciones) AS txtObservacionDetalle,
            ISNULL(t.numHoras, a.numHoras)                 AS numHorasDetalle
    FROM registro.TMD_REGISTRO_HORAMES r
    LEFT JOIN registro.TMD_REGISTRO_HORAMES_ACT a
           ON a.ideRegistroHorames = r.ideRegistroHorames AND a.flgEstado = 1
    LEFT JOIN registro.TMD_REGISTRO_HORAMES_ACTTAREA t
           ON t.ideRegistroHoramesAct = a.ideRegistroHoramesAct AND t.flgEstado = 1
    WHERE r.ideEmpleado = @ideEmpleado
      AND r.numAnio = @numAnio
      AND r.numMes  = @numMes
      AND r.flgEstado = 1
    ORDER BY r.codProyecto, a.ideRegistroHoramesAct, t.ideRegistroHoramesActtarea;
END
GO
