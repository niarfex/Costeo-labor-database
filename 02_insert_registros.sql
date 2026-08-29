USE [COSTO_LABOR];
GO

/* Obligatorio: registro.TG_TIPO_DATO tiene un indice filtrado y rechaza
   cualquier DML compilado sin estas opciones. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* Semilla base. Se inserta solo lo que falta para poder re-ejecutar el script
   sin chocar contra los indices unicos de codigo. */

INSERT INTO general.TG_CONFIGURACION
      (txtCodigoConfiguracion, numParametro, txtParametro, numMinimo, numMaximo, txtDescripcion, flgEstado)
SELECT s.cod, s.num, s.txt, s.minimo, s.maximo, s.des, 1
FROM (VALUES
      ('TIEMPO_INACTIVIDAD',           30, '', 0,  0, 'Tiempo de inactividad en minutos'),
      ('MAX_CANT_INTENTO_FALLIDO',      5, '', 0, 25, 'Cantidad de intentos fallidos antes del bloqueo'),
      ('TIEMPO_BLOQUEO_INICIO_SESION', 15, '', 0, 30, 'Tiempo de bloqueo de inicio de sesion en minutos')
     ) AS s(cod, num, txt, minimo, maximo, des)
WHERE NOT EXISTS (SELECT 1 FROM general.TG_CONFIGURACION d
                  WHERE d.txtCodigoConfiguracion = s.cod);
GO

/* La tilde de NUMERO la corrige 06_update_registros.sql con NCHAR, para no
   depender de la codificacion con que se guarde este archivo. */
INSERT INTO registro.TG_TIPO_DATO (codTipoDato, nomTipodato, flgEstado, fecCreacion, txtUsuarioCreacion)
SELECT s.cod, s.nom, 1, GETDATE(), 'SYSTEM_COSTOLABOR'
FROM (VALUES
      ('TEXTO',  'TEXTO'),
      ('NUMERO', 'NUMERO')
     ) AS s(cod, nom)
WHERE NOT EXISTS (SELECT 1 FROM registro.TG_TIPO_DATO d
                  WHERE d.codTipoDato = s.cod);
GO
