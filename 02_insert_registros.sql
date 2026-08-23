USE [COSTO_LABOR];

INSERT INTO general.TG_CONFIGURACION(txtCodigoConfiguracion,numParametro,txtParametro,numMinimo,numMaximo,txtDescripcion,flgEstado) 
VALUES('TIEMPO_INACTIVIDAD',30,'',0,0,'Tiempo de inactividad en minutos',1);
--
INSERT INTO registro.TG_TIPO_DATO(codTipoDato,nomTipodato,flgEstado,fecCreacion,txtUsuarioCreacion) 
VALUES('TEXTO','TEXTO',1,GETDATE(),'SYSTEM_COSTOLABOR');
INSERT INTO registro.TG_TIPO_DATO(codTipoDato,nomTipodato,flgEstado,fecCreacion,txtUsuarioCreacion) 
VALUES('NUMERO','NÚMERO',1,GETDATE(),'SYSTEM_COSTOLABOR');