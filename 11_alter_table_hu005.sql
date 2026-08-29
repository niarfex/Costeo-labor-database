/* =========================================================================
   HU-005 / HU-006 - Correcciones estructurales sobre 01_create_table.sql

   Tres omisiones que impiden implementar el registro de horas:

   1. Las tablas de detalle ACT y ACTTAREA guardan las horas y las
      observaciones, pero no tienen donde guardar el texto de la actividad
      ni el de la tarea. El modal de captura de la HU-005 (CA-03) los pide
      como campos de texto libre, segun el mockup v2.

   2. Las tablas de validacion tienen un unico txtComentario. El CA-05 pide
      el historial cronologico de la observacion del jefe Y la respuesta de
      subsanacion del trabajador, cada una con su autor y fecha. Con un solo
      campo, la respuesta pisa la observacion.

   3. La cabecera TMD_REGISTRO_HORADIA no tiene donde guardar la
      observacion a nivel de proyecto del formulario simple del CA-03.

   4. Falta la unicidad que necesita la consolidacion automatica del CA-04:
      una fila por empleado, proyecto y fecha en el registro diario, y una
      por empleado y proyecto en el consolidado mensual.

   El mismo defecto existe en las tablas mensuales de la HU-006, por eso se
   corrigen juntas: es la misma omision repetida.
   ========================================================================= */

USE [COSTO_LABOR];
GO

/* -------------------------------------------------------------------------
   1. Texto de la actividad y de la tarea
   ------------------------------------------------------------------------- */

-- Se usa varchar(500), la misma longitud que txtActividad en
-- registro.TMD_DISTRIBUCION_GIP_DETALLE, para no tener dos criterios.
IF COL_LENGTH('registro.TMD_REGISTRO_HORADIA_ACT', 'txtActividad') IS NULL
    ALTER TABLE registro.TMD_REGISTRO_HORADIA_ACT ADD txtActividad varchar(500) NULL;
GO

IF COL_LENGTH('registro.TMD_REGISTRO_HORADIA_ACTTAREA', 'txtTarea') IS NULL
    ALTER TABLE registro.TMD_REGISTRO_HORADIA_ACTTAREA ADD txtTarea varchar(500) NULL;
GO

IF COL_LENGTH('registro.TMD_REGISTRO_HORAMES_ACT', 'txtActividad') IS NULL
    ALTER TABLE registro.TMD_REGISTRO_HORAMES_ACT ADD txtActividad varchar(500) NULL;
GO

IF COL_LENGTH('registro.TMD_REGISTRO_HORAMES_ACTTAREA', 'txtTarea') IS NULL
    ALTER TABLE registro.TMD_REGISTRO_HORAMES_ACTTAREA ADD txtTarea varchar(500) NULL;
GO

/* -------------------------------------------------------------------------
   1.b Observacion a nivel de proyecto

   El CA-03 define un "formulario simple" (flgRegActividad = 0 y
   flgRegTareaxActividad = 0) que guarda Observacion y Horas directamente en
   la cabecera, pero la tabla no tiene columna para esa observacion.
   ------------------------------------------------------------------------- */

IF COL_LENGTH('registro.TMD_REGISTRO_HORADIA', 'txtObservaciones') IS NULL
    ALTER TABLE registro.TMD_REGISTRO_HORADIA ADD txtObservaciones varchar(250) NULL;
GO

IF COL_LENGTH('registro.TMD_REGISTRO_HORAMES', 'txtObservaciones') IS NULL
    ALTER TABLE registro.TMD_REGISTRO_HORAMES ADD txtObservaciones varchar(250) NULL;
GO

/* -------------------------------------------------------------------------
   2. Respuesta de subsanacion en las tablas de validacion

   Cada fila representa un ciclo completo: el jefe observa (txtComentario,
   txtUsuarioCreacion, fecCreacion) y el trabajador responde (txtRespuesta,
   txtUsuarioRespuesta, fecRespuesta). Varias filas por registro componen el
   historial cronologico que pide el CA-05.
   ------------------------------------------------------------------------- */

IF COL_LENGTH('registro.TMD_REGISTRO_HORADIA_VALIDACION', 'txtRespuesta') IS NULL
    ALTER TABLE registro.TMD_REGISTRO_HORADIA_VALIDACION ADD
        txtRespuesta        varchar(250) NULL,
        fecRespuesta        datetime     NULL,
        txtUsuarioRespuesta varchar(30)  NULL;
GO

IF COL_LENGTH('registro.TMD_REGISTRO_HORAMES_VALIDACION', 'txtRespuesta') IS NULL
    ALTER TABLE registro.TMD_REGISTRO_HORAMES_VALIDACION ADD
        txtRespuesta        varchar(250) NULL,
        fecRespuesta        datetime     NULL,
        txtUsuarioRespuesta varchar(30)  NULL;
GO

/* -------------------------------------------------------------------------
   3. Documentacion de las columnas nuevas
   ------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sys.extended_properties
               WHERE major_id = OBJECT_ID('registro.TMD_REGISTRO_HORADIA_ACT')
                 AND minor_id = COLUMNPROPERTY(OBJECT_ID('registro.TMD_REGISTRO_HORADIA_ACT'), 'txtActividad', 'ColumnId')
                 AND name = 'MS_Description')
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Descripcion libre de la actividad realizada',
         @level0type=N'SCHEMA', @level0name=N'registro',
         @level1type=N'TABLE',  @level1name=N'TMD_REGISTRO_HORADIA_ACT',
         @level2type=N'COLUMN', @level2name=N'txtActividad';
GO

IF NOT EXISTS (SELECT 1 FROM sys.extended_properties
               WHERE major_id = OBJECT_ID('registro.TMD_REGISTRO_HORADIA_ACTTAREA')
                 AND minor_id = COLUMNPROPERTY(OBJECT_ID('registro.TMD_REGISTRO_HORADIA_ACTTAREA'), 'txtTarea', 'ColumnId')
                 AND name = 'MS_Description')
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Descripcion libre de la tarea dentro de la actividad',
         @level0type=N'SCHEMA', @level0name=N'registro',
         @level1type=N'TABLE',  @level1name=N'TMD_REGISTRO_HORADIA_ACTTAREA',
         @level2type=N'COLUMN', @level2name=N'txtTarea';
GO

IF NOT EXISTS (SELECT 1 FROM sys.extended_properties
               WHERE major_id = OBJECT_ID('registro.TMD_REGISTRO_HORADIA_VALIDACION')
                 AND minor_id = COLUMNPROPERTY(OBJECT_ID('registro.TMD_REGISTRO_HORADIA_VALIDACION'), 'txtRespuesta', 'ColumnId')
                 AND name = 'MS_Description')
    EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'Descargo del trabajador al subsanar la observacion',
         @level0type=N'SCHEMA', @level0name=N'registro',
         @level1type=N'TABLE',  @level1name=N'TMD_REGISTRO_HORADIA_VALIDACION',
         @level2type=N'COLUMN', @level2name=N'txtRespuesta';
GO
