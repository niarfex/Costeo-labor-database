/* =========================================================================
   39 - Base comun de los reportes de resultado (HU-009, HU-010 y HU-012)

   Complementa el script 38 (reportes de horas, que ya da los periodos
   cerrados con registro.usp_ReporteHoras_ListarPeriodosCerrados y las
   opciones de menu de HU-011, HU-013 y HU-014):

     - proceso.usp_Reporte_ListarFuentes: las fuentes de financiamiento del
       filtro "Fte. Fto." (HU-009 y HU-010), las mismas que muestran los
       reportes.
     - Las opciones de menu que ya existian desde el script 08
       (REP_GASTO_OPERATIVO, REP_COMPENSACION y PROY_RESOLUCION) se asignan a
       los perfiles del CA de seguridad de cada historia:

         HU-009 Gasto operativo            CONTADOR
         HU-010 Compensacion               CONTADOR, JEFE, ADMINISTRADOR
         HU-012 Proyecto de resolucion     CONTADOR, JEFE, ADMINISTRADOR

       Los jefes de la Gerencia de Operaciones y de la GIP usan el perfil JEFE.

     - REP_MANO_OBRA ("Costo de mano de obra") se da de baja: ninguna historia
       la define y su pantalla no existe; la mano de obra sale en el
       consolidado del procesamiento (HU-008).
     - Corrige las tildes de las opciones de los scripts 36, 37 y 38 en las
       bases donde se aplicaron sin BOM.

   La auditoria de cada consulta y descarga usa general.usp_Auditoria_Registrar,
   que ya existe.

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

/* ---------------------------------------------------------------------------
   Fuentes de financiamiento del periodo: las mismas que muestran los
   reportes: la categoria de cada proyecto (Categorizacion de proyectos) en
   la vista de reporte de la compensacion. PROINVERSION es la parte de la GIP
   del gasto operativo. "Categoria Desconocida" no es una fuente: es la marca de los
   proyectos sin categoria, y sus montos solo aparecen con el filtro "Todas".
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE proceso.usp_Reporte_ListarFuentes
    @numAnio int,
    @numMes  int
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idePeriodo bigint = (SELECT idePeriodo FROM registro.TMC_PERIODO
                                  WHERE numAnio = @numAnio AND numMes = @numMes);

    SELECT codFuente
    FROM (
        SELECT TRIM(dc.txtCategoria) AS codFuente
        FROM proceso.VW_DISTRIBUCION_COMPENSACION_REPORTE dc
        WHERE dc.idePeriodo = @idePeriodo

        UNION
        SELECT 'PROINVERSION' WHERE @idePeriodo IS NOT NULL
    ) f
    WHERE NULLIF(codFuente, '') IS NOT NULL
      AND codFuente <> 'Categoria Desconocida'
    ORDER BY CASE codFuente WHEN 'FA' THEN 1 WHEN 'PAR' THEN 2 WHEN '28E' THEN 3 WHEN 'TUCARI' THEN 4
                            WHEN 'TUQUIAR' THEN 5 WHEN 'PROINVERSION' THEN 7 ELSE 6 END, codFuente;
END
GO

/* ---------------------------------------------------------------------------
   Opciones de menu de HU-009, HU-010 y HU-012 (script 08): nombre con
   tildes y activas. Las rutas son las que ya tenian.
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

UPDATE o
SET o.nomOpcion = d.nomOpcion,
    o.flgEstado = 1,
    o.fecActualizacion = GETDATE(),
    o.txtUsuarioActualizacion = @usuario
FROM seguridad.TG_OPCION o
JOIN (VALUES
   ('REP_GASTO_OPERATIVO', 'Gasto operativo por proyecto'),
   ('REP_COMPENSACION',    'Compensación por proyecto'),
   ('PROY_RESOLUCION',     'Proyecto de resolución')
) AS d(codOpcion, nomOpcion) ON d.codOpcion = o.codOpcion
WHERE o.nomOpcion <> d.nomOpcion OR o.flgEstado <> 1;

-- Sin historia ni pantalla: se retira del menu de todos los perfiles.
UPDATE seguridad.TG_OPCION
SET flgEstado = 0, fecActualizacion = GETDATE(), txtUsuarioActualizacion = @usuario
WHERE codOpcion = 'REP_MANO_OBRA' AND flgEstado <> 0;

-- Los scripts 36, 37 y 38 se guardaron sin BOM y, corridos con sqlcmd, dejaron
-- las tildes de sus opciones como dos caracteres.
UPDATE seguridad.TG_OPCION
SET nomOpcion = 'Actualización de estado de proyectos', fecActualizacion = GETDATE(),
    txtUsuarioActualizacion = @usuario
WHERE codOpcion = 'ESTADO_PROYECTOS' AND nomOpcion <> 'Actualización de estado de proyectos';

UPDATE seguridad.TG_OPCION
SET nomOpcion = 'Categorización de proyectos', fecActualizacion = GETDATE(),
    txtUsuarioActualizacion = @usuario
WHERE codOpcion = 'CATEGORIZACION_PROYECTOS' AND nomOpcion <> 'Categorización de proyectos';

UPDATE seguridad.TG_OPCION
SET nomOpcion = 'Detallado por trabajador por día', fecActualizacion = GETDATE(),
    txtUsuarioActualizacion = @usuario
WHERE codOpcion = 'REP_DETALLE_DIA' AND nomOpcion <> 'Detallado por trabajador por día';
GO

/* ---------------------------------------------------------------------------
   Perfiles de cada reporte. Solo agrega las asignaciones que nunca
   existieron: si el administrador quito una desde Perfiles y permisos, volver
   a correr el script no la repone. El titulo REPORTES va con cada perfil.
   --------------------------------------------------------------------------- */
DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES
   ('CONTADOR',      'REPORTES'),
   ('JEFE',          'REPORTES'),
   ('ADMINISTRADOR', 'REPORTES'),

   ('CONTADOR',      'REP_GASTO_OPERATIVO'),

   ('CONTADOR',      'REP_COMPENSACION'),
   ('JEFE',          'REP_COMPENSACION'),
   ('ADMINISTRADOR', 'REP_COMPENSACION'),

   ('CONTADOR',      'PROY_RESOLUCION'),
   ('JEFE',          'PROY_RESOLUCION'),
   ('ADMINISTRADOR', 'PROY_RESOLUCION')
) AS a(codPerfil, codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = a.codPerfil
JOIN seguridad.TG_OPCION  op ON op.codOpcion = a.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
