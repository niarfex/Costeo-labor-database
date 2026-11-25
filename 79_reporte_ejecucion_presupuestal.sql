/* =========================================================================
   79 - Reporte de ejecucion presupuestal por meses (Encargo N.2)

   Pedido de Efrain (24/11): el Contador genera la ejecucion presupuestal de
   un anio, mes por mes, para compararla con el reporte de gastos del
   sistema. Es el "Anexo N.1 - Presupuesto ejecutado operativo" que usa
   Contabilidad. Solo sale de SPRING; no depende del procesamiento del
   periodo ni excluye proyectos.

   Clasificador: cada linea de BD_SPRING.dbo.voucherdetail trae en
   ReferenciaFiscal02 su clasificador presupuestal. El maestro es
   BD_SPRING.dbo.AC_ReferenciaFiscal del anio del reporte, en su ultima
   version (MAX(Version)): tipo de referencia '02' para los egresos y '04'
   para los ingresos (1, 4 y 5.1). El codigo es posicional: "22 1 1" es el
   rubro 2.2.1.1 y "22 710" el 2.2.7.10.

   1. proceso.TMC_EJECUCION_PRESUPUESTAL_RUBRO: las filas del reporte, en el
      orden y con el texto del Excel de Contabilidad. Cada fila es:
        SPRING   suma de las lineas cuyo clasificador empieza con txtPrefijo,
                 por numSigno (los ingresos son abonos: -1 los muestra en
                 positivo).
        FORMULA  se calcula con otras filas (codFormula):
                   TRANSFERENCIAS_NETAS   5.1 - 5.2
                   RESULTADO_OPERACION    1 - 2
                   RESULTADO_ECONOMICO    resultado de operacion - 3 + 4 + 5
                   EJERCICIOS_ANTERIORES  lo que falta para que el saldo final
                                          no sea negativo (resultado economico
                                          + 6, si es menor que cero)
                   SALDO_FINAL            resultado economico + 6 + ejercicios
                                          anteriores
                   GIP_TOTAL              los rubros GIP: 2.2, 2.3.3, 2.3.6,
                                          2.3.8.1 a 2.3.8.3, 2.5.2 y 2.5.4.1
        TITULO   sin montos.
      Las formulas se probaron contra el Excel de enero a junio 2025.

   2. general.TG_CONFIGURACION EJEC_PRES_CLASES_CTA: clases de cuenta que
      entran (primer digito de la cuenta). Por ahora '67', cuentas de gasto
      e ingreso, que es como cuadra con el Excel de Contabilidad: el mismo
      clasificador se usa tambien en cuentas de orden (clase 0) de proyectos.
      Vacio = todas las cuentas. Se cambia sin tocar codigo.

   3. proceso.usp_Reporte_EjecucionPresupuestal @numAnio: una fila por rubro
      con los doce meses y el total del anio. Los vouchers anulados no
      entran.

   4. Opcion de menu EJECUCION_PRESUPUESTAL en Reportes, solo para el perfil
      CONTADOR.

   Errores nuevos:
     50180  la base de datos BD_SPRING no esta disponible
     50181  anio fuera de rango

   Idempotente: la estructura del reporte solo se carga si la tabla esta
   vacia, y la opcion y su asignacion solo si nunca existieron.
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

IF NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'REPORTES')
    THROW 50149, 'Falta la opcion REPORTES en seguridad.TG_OPCION (script 08).', 1;
GO

/* -------------------------------------------------------------------------
   1. Estructura del reporte
   ------------------------------------------------------------------------- */

IF OBJECT_ID('proceso.TMC_EJECUCION_PRESUPUESTAL_RUBRO') IS NULL
BEGIN
    CREATE TABLE proceso.TMC_EJECUCION_PRESUPUESTAL_RUBRO(
        ideRubro bigint IDENTITY(1,1) NOT NULL,
        numOrden int NOT NULL,
        txtCodigo varchar(20) NULL,
        txtRubro nvarchar(200) NOT NULL,
        codTipo varchar(10) NOT NULL,
        txtPrefijo varchar(30) NULL,
        numSigno smallint NOT NULL CONSTRAINT DF_TMC_EJECUCION_PRESUPUESTAL_RUBRO_numSigno DEFAULT (1),
        codFormula varchar(30) NULL,
        flgNegrita bit NOT NULL CONSTRAINT DF_TMC_EJECUCION_PRESUPUESTAL_RUBRO_flgNegrita DEFAULT (0),
        flgResaltado bit NOT NULL CONSTRAINT DF_TMC_EJECUCION_PRESUPUESTAL_RUBRO_flgResaltado DEFAULT (0),
        numNivel tinyint NOT NULL CONSTRAINT DF_TMC_EJECUCION_PRESUPUESTAL_RUBRO_numNivel DEFAULT (1),
        flgEstado int NOT NULL CONSTRAINT DF_TMC_EJECUCION_PRESUPUESTAL_RUBRO_flgEstado DEFAULT (1),
        fecCreacion datetime NULL CONSTRAINT DF_TMC_EJECUCION_PRESUPUESTAL_RUBRO_fecCreacion DEFAULT (GETDATE()),
        txtUsuarioCreacion varchar(100) NULL,
        fecActualizacion datetime NULL,
        txtUsuarioActualizacion varchar(100) NULL,
        CONSTRAINT PK_TMC_EJECUCION_PRESUPUESTAL_RUBRO PRIMARY KEY CLUSTERED (ideRubro ASC),
        CONSTRAINT CK_TMC_EJECUCION_PRESUPUESTAL_RUBRO_TIPO CHECK (codTipo IN ('SPRING', 'FORMULA', 'TITULO')),
        CONSTRAINT CK_TMC_EJECUCION_PRESUPUESTAL_RUBRO_SIGNO CHECK (numSigno IN (1, -1))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM proceso.TMC_EJECUCION_PRESUPUESTAL_RUBRO)
    INSERT INTO proceso.TMC_EJECUCION_PRESUPUESTAL_RUBRO
          (numOrden, txtCodigo, txtRubro, codTipo, txtPrefijo, numSigno, codFormula,
           flgNegrita, flgResaltado, numNivel, txtUsuarioCreacion)
    SELECT f.numOrden, f.txtCodigo, f.txtRubro, f.codTipo, f.txtPrefijo, f.numSigno, f.codFormula,
           f.flgNegrita, f.flgResaltado, f.numNivel, 'SYSTEM_COSTOLABOR'
    FROM (VALUES
        (10, NULL, N'PRESUPUESTO DE OPERACIÓN', 'TITULO', NULL, 1, NULL, 1, 1, 1),
        (20, N'1', N'1     INGRESOS', 'SPRING', N'1', -1, NULL, 1, 0, 1),
        (30, N'1.1', N'1.1  Venta de Bienes', 'SPRING', N'11', -1, NULL, 0, 0, 2),
        (40, N'1.2', N'1.2  Venta de Servicios', 'SPRING', N'12', -1, NULL, 0, 0, 2),
        (50, N'1.3', N'1.3  Ingresos Financieros', 'SPRING', N'13', -1, NULL, 1, 0, 2),
        (60, N'1.4', N'1.4  Ingresos por participacion o dividendos', 'SPRING', N'14', -1, NULL, 0, 0, 2),
        (70, N'1.5', N'1.5  Ingresos complementarios', 'SPRING', N'15', -1, NULL, 0, 0, 2),
        (80, N'1.6', N'1.6  Otros', 'SPRING', N'16', -1, NULL, 1, 0, 2),
        (90, N'2', N'2     EGRESOS', 'SPRING', N'2', 1, NULL, 1, 1, 1),
        (100, N'2.1', N'2.1  Compra de Bienes', 'SPRING', N'21', 1, NULL, 1, 1, 2),
        (110, N'2.1.1', N'2.1.1 Insumos y suministros', 'SPRING', N'21 1', 1, NULL, 0, 0, 3),
        (120, N'2.1.2', N'2.1.2 Combustibles y lubricantes', 'SPRING', N'21 2', 1, NULL, 0, 0, 3),
        (130, N'2.1.3', N'2.1.3   Otros', 'SPRING', N'21 3', 1, NULL, 0, 0, 3),
        (140, N'2.2', N'2.2. Gastos de personal (GIP)', 'SPRING', N'22', 1, NULL, 1, 1, 2),
        (150, N'2.2.1', N'2.2.1   Sueldos y Salarios  (GIP)', 'SPRING', N'22 1', 1, NULL, 1, 1, 3),
        (160, N'2.2.1.1', N'2.2.1.1   Básica (GIP)', 'SPRING', N'22 1 1', 1, NULL, 0, 0, 4),
        (170, N'2.2.1.2', N'2.2.1.2   Bonificaciones (GIP)', 'SPRING', N'22 1 2', 1, NULL, 0, 0, 4),
        (180, N'2.2.1.3', N'2.2.1.3   Gratificaciones (GIP)', 'SPRING', N'22 1 3', 1, NULL, 0, 0, 4),
        (190, N'2.2.1.4', N'2.2.1.4   Asignaciones (GIP)', 'SPRING', N'22 1 4', 1, NULL, 0, 0, 4),
        (200, N'2.2.1.5', N'2.2.1.5   Horas Extras (GIP)', 'SPRING', N'22 1 5', 1, NULL, 0, 0, 4),
        (210, N'2.2.1.6', N'2.2.1.6   Otros (GIP)', 'SPRING', N'22 1 6', 1, NULL, 0, 0, 4),
        (220, N'2.2.2', N'2.2.2. Compensación por Tiempo de Servicios (GIP)', 'SPRING', N'22 2', 1, NULL, 0, 0, 3),
        (230, N'2.2.3', N'2.2.3. Seguridad y previsión social (GIP)', 'SPRING', N'22 3', 1, NULL, 0, 0, 3),
        (240, N'2.2.4', N'2.2.4. Dietas del directorio (GIP)', 'SPRING', N'22 4', 1, NULL, 0, 0, 3),
        (250, N'2.2.5', N'2.2.5. Capacitación (GIP)', 'SPRING', N'22 5', 1, NULL, 0, 0, 3),
        (260, N'2.2.6', N'2.2.6. Jubilaciones y pensiones (GIP)', 'SPRING', N'22 6', 1, NULL, 0, 0, 3),
        (270, N'2.2.7', N'2.2.7   Otros gastos de personal (GIP)', 'SPRING', N'22 7', 1, NULL, 1, 1, 3),
        (280, N'2.2.7.1', N'2.2.7.1  Refrigerio (GIP)', 'SPRING', N'22 7 1', 1, NULL, 0, 0, 4),
        (290, N'2.2.7.2', N'2.2.7.2  Uniformes (GIP)', 'SPRING', N'22 7 2', 1, NULL, 0, 0, 4),
        (300, N'2.2.7.3', N'2.2.7.3  Asistencia Médica (GIP)', 'SPRING', N'22 7 3', 1, NULL, 0, 0, 4),
        (310, N'2.2.7.4', N'2.2.7.4  Seguro complementario de alto riesgo (GIP)', 'SPRING', N'22 7 4', 1, NULL, 0, 0, 4),
        (320, N'2.2.7.5', N'2.2.7.5  Pago de indemnizac.por cese de relac.laboral(GIP)', 'SPRING', N'22 7 5', 1, NULL, 0, 0, 4),
        (330, N'2.2.7.6', N'2.2.7.6  Incentivos por retiro voluntario (GIP)', 'SPRING', N'22 7 6', 1, NULL, 0, 0, 4),
        (340, N'2.2.7.7', N'2.2.7.7  Celebraciones (GIP)', 'SPRING', N'22 7 7', 1, NULL, 0, 0, 4),
        (350, N'2.2.7.8', N'2.2.7.8  Bono de Productividad (GIP)', 'SPRING', N'22 7 8', 1, NULL, 0, 0, 4),
        (360, N'2.2.7.9', N'2.2.7.9  Participación de trabajadores (GIP)', 'SPRING', N'22 7 9', 1, NULL, 0, 0, 4),
        (370, N'2.2.7.10', N'2.2.7.10  Otros (GIP)', 'SPRING', N'22 710', 1, NULL, 0, 0, 4),
        (380, N'2.3', N'2.3  Servicios  prestados por terceros', 'SPRING', N'23', 1, NULL, 1, 1, 2),
        (390, N'2.3.1', N'2.3.1. Transporte y almacenamiento', 'SPRING', N'23 1', 1, NULL, 0, 0, 3),
        (400, N'2.3.2', N'2.3.2. Tarifas de servicios públicos', 'SPRING', N'23 2', 1, NULL, 0, 0, 3),
        (410, N'2.3.3', N'2.3.3  Honorarios profesionales (GIP)', 'SPRING', N'23 3', 1, NULL, 1, 1, 3),
        (420, N'2.3.3.1', N'2.3.3.1  Auditorías (GIP)', 'SPRING', N'23 3 1', 1, NULL, 0, 0, 4),
        (430, N'2.3.3.2', N'2.3.3.2  Consultorías (GIP)', 'SPRING', N'23 3 2', 1, NULL, 0, 0, 4),
        (440, N'2.3.3.3', N'2.3.3.3  Asesorías (GIP)', 'SPRING', N'23 3 3', 1, NULL, 0, 0, 4),
        (450, N'2.3.3.4', N'2.3.3.4  Otros servicios no personales (GIP)', 'SPRING', N'23 3 4', 1, NULL, 0, 0, 4),
        (460, N'2.3.4', N'2.3.4  Mantenimiento y reparación', 'SPRING', N'23 4', 1, NULL, 0, 0, 3),
        (470, N'2.3.5', N'2.3.5  Alquileres', 'SPRING', N'23 5', 1, NULL, 0, 0, 3),
        (480, N'2.3.6', N'2.3.6   Serv. de vigilancia, guardiania y limp. (GIP)', 'SPRING', N'23 6', 1, NULL, 1, 1, 3),
        (490, N'2.3.6.1', N'2.3.6.1  Vigilancia (GIP)', 'SPRING', N'23 6 1', 1, NULL, 0, 0, 4),
        (500, N'2.3.6.2', N'2.3.6.2  Guardianía (GIP)', 'SPRING', N'23 6 2', 1, NULL, 0, 0, 4),
        (510, N'2.3.6.3', N'2.3.6.3  Limpieza (GIP)', 'SPRING', N'23 6 3', 1, NULL, 0, 0, 4),
        (520, N'2.3.7', N'2.3.7  Publicidad y publicaciones', 'SPRING', N'23 7', 1, NULL, 0, 0, 3),
        (530, N'2.3.8', N'2.3.8   Otros', 'SPRING', N'23 8', 1, NULL, 1, 1, 3),
        (540, N'2.3.8.1', N'2.3.8.1  Servicio de mensajería y correspondencia (GIP)', 'SPRING', N'23 8 1', 1, NULL, 0, 0, 4),
        (550, N'2.3.8.2', N'2.3.8.2  Provisión de personal por coop. y services (GIP)', 'SPRING', N'23 8 2', 1, NULL, 0, 0, 4),
        (560, N'2.3.8.3', N'2.3.8.3  Otros relacionados a GIP (GIP)', 'SPRING', N'23 8 3', 1, NULL, 0, 0, 4),
        (570, N'2.3.8.4', N'2.3.8.4  Otros no relacionados a GIP', 'SPRING', N'23 8 4', 1, NULL, 0, 0, 4),
        (580, N'2.4', N'2.4  Tributos', 'SPRING', N'24', 1, NULL, 1, 1, 2),
        (590, N'2.4.1', N'2.4.1  Impuesto a las Transacciones Financieras - ITF', 'SPRING', N'24 1', 1, NULL, 0, 0, 3),
        (600, N'2.4.2', N'2.4.2 Otros impuestos y contribuciones', 'SPRING', N'24 2', 1, NULL, 0, 0, 3),
        (610, N'2.5', N'2.5  Gastos diversos de Gestion', 'SPRING', N'25', 1, NULL, 1, 1, 2),
        (620, N'2.5.1', N'2.5.1. Seguros', 'SPRING', N'25 1', 1, NULL, 0, 0, 3),
        (630, N'2.5.2', N'2.5.2. Viáticos (GIP)', 'SPRING', N'25 2', 1, NULL, 0, 0, 3),
        (640, N'2.5.3', N'2.5.3. Gastos de representación', 'SPRING', N'25 3', 1, NULL, 0, 0, 3),
        (650, N'2.5.4', N'2.5.4   Otros', 'SPRING', N'25 4', 1, NULL, 0, 0, 3),
        (660, N'2.5.4.1', N'2.5.4.1  Otros relacionados a GIP (GIP)', 'SPRING', N'25 4 1', 1, NULL, 0, 0, 4),
        (670, N'2.5.4.2', N'2.5.4.2  Otros no relacionados a GIP', 'SPRING', N'25 4 2', 1, NULL, 0, 0, 4),
        (680, N'2.6', N'2.6. Gastos financieros', 'SPRING', N'26', 1, NULL, 1, 1, 2),
        (690, N'2.7', N'2.7.  Otros', 'SPRING', N'27', 1, NULL, 1, 1, 2),
        (700, NULL, N'RESULTADO DE OPERACION', 'FORMULA', NULL, 1, N'RESULTADO_OPERACION', 1, 0, 1),
        (710, N'3', N'3  GASTOS DE CAPITAL', 'SPRING', N'3', 1, NULL, 1, 1, 1),
        (720, N'3.1', N'3.1  Presupuesto de Inversiones - FBK', 'SPRING', N'31', 1, NULL, 1, 0, 2),
        (730, N'3.1.1', N'3.1.1    Proyecto de Inversion', 'SPRING', N'31 1', 1, NULL, 0, 0, 3),
        (740, N'3.1.2', N'3.1.2  Gastos de capital no ligados a proyectos de Inversión', 'SPRING', N'31 2', 1, NULL, 1, 0, 3),
        (750, N'3.2', N'3.2  Inversion Financiera', 'SPRING', N'32', 1, NULL, 1, 0, 2),
        (760, N'3.3', N'3.3. Otros', 'SPRING', N'33', 1, NULL, 1, 0, 2),
        (770, N'4', N'4  INGRESOS DE CAPITAL', 'SPRING', N'4', -1, NULL, 1, 1, 1),
        (780, N'4.1', N'4.1  Aportes de Capital', 'SPRING', N'41', -1, NULL, 0, 0, 2),
        (790, N'4.2', N'4.2  Ventas de activo fijo', 'SPRING', N'42', -1, NULL, 0, 0, 2),
        (800, N'4.3', N'4.3  Otros', 'SPRING', N'43', -1, NULL, 0, 0, 2),
        (810, N'5', N'5 TRANSFERENCIAS NETAS', 'FORMULA', NULL, 1, N'TRANSFERENCIAS_NETAS', 1, 1, 1),
        (820, N'5.1', N'5.1     Ingresos por Transferencias', 'SPRING', N'51', -1, NULL, 0, 0, 2),
        (830, N'5.2', N'5.2     Egresos por Transferencias', 'SPRING', N'52', 1, NULL, 0, 0, 2),
        (840, NULL, N'RESULTADO ECONOMICO', 'FORMULA', NULL, 1, N'RESULTADO_ECONOMICO', 1, 0, 1),
        (850, N'6', N'6   FINANCIAMIENTO NETO', 'SPRING', N'6', 1, NULL, 1, 1, 1),
        (860, N'6.1', N'6.1  Financiamiento Externo Neto', 'SPRING', N'61', 1, NULL, 1, 1, 2),
        (870, N'6.1.1', N'6.1.1.  Financiamiento largo plazo', 'SPRING', N'61 1', 1, NULL, 1, 1, 3),
        (880, N'6.1.1.1', N'6.1.1.1      Desembolsos', 'SPRING', N'61 1 1', 1, NULL, 0, 0, 4),
        (890, N'6.1.1.2', N'6.1.1.2      Servicios  de Deuda', 'SPRING', N'61 1 2', 1, NULL, 0, 1, 4),
        (900, N'6.1.1.2.1', N'6.1.1.2.1         Amortizacion', 'SPRING', N'61 1 2 1', 1, NULL, 0, 0, 5),
        (910, N'6.1.1.2.2', N'6.1.1.2.2         Intereses y comisiones de la deuda', 'SPRING', N'61 1 2 2', 1, NULL, 0, 0, 5),
        (920, N'6.1.2', N'6.1.2. Financiamiento corto plazo', 'SPRING', N'61 2', 1, NULL, 1, 1, 3),
        (930, N'6.1.2.1', N'6.1.2.1      Desembolsos', 'SPRING', N'61 2 1', 1, NULL, 0, 0, 4),
        (940, N'6.1.2.2', N'6.1.2.2      Servicio de la Deuda', 'SPRING', N'61 2 2', 1, NULL, 0, 1, 4),
        (950, N'6.1.2.2.1', N'6.1.2.2.1         Amortizacion', 'SPRING', N'61 2 2 1', 1, NULL, 0, 0, 5),
        (960, N'6.1.2.2.2', N'6.1.2.2.2         Intereses y comisiones de la deuda', 'SPRING', N'61 2 2 2', 1, NULL, 0, 0, 5),
        (970, N'6.2', N'6.2  Financiamiento Interno Neto', 'SPRING', N'62', 1, NULL, 1, 1, 2),
        (980, N'6.2.1', N'6.2.1. Financiamiento Largo PLazo', 'SPRING', N'62 1', 1, NULL, 1, 1, 3),
        (990, N'6.2.1.1', N'6.2.1.1       Desembolsos', 'SPRING', N'62 1 1', 1, NULL, 0, 0, 4),
        (1000, N'6.2.1.2', N'6.2.1.2       Servicio de la Deuda', 'SPRING', N'62 1 2', 1, NULL, 0, 1, 4),
        (1010, N'6.2.1.2.1', N'6.2.1.2.1         Amortizacion', 'SPRING', N'62 1 2 1', 1, NULL, 0, 0, 5),
        (1020, N'6.2.1.2.2', N'6.2.1.2.2         Intereses y comisiones de la deuda', 'SPRING', N'62 1 2 2', 1, NULL, 0, 0, 5),
        (1030, N'6.2.2', N'6.2.2. Financiamiento  Corto Plazo', 'SPRING', N'62 2', 1, NULL, 1, 1, 3),
        (1040, N'6.2.2.1', N'6.2.2.1      Desembolsos', 'SPRING', N'62 2 1', 1, NULL, 0, 0, 4),
        (1050, N'6.2.2.2', N'6.2.2.2      Servicio de la Deuda', 'SPRING', N'62 2 2', 1, NULL, 0, 1, 4),
        (1060, N'6.2.2.2.1', N'6.2.2.2.1         Amortizacion', 'SPRING', N'62 2 2 1', 1, NULL, 0, 0, 5),
        (1070, N'6.2.2.2.2', N'6.2.2.2.2         Intereses y comisiones de la Deuda', 'SPRING', N'62 2 2 2', 1, NULL, 0, 0, 5),
        (1080, NULL, N'RESULTADO DE EJERCICIOS ANTERIORES', 'FORMULA', NULL, 1, N'EJERCICIOS_ANTERIORES', 1, 0, 1),
        (1090, NULL, N'SALDO FINAL', 'FORMULA', NULL, 1, N'SALDO_FINAL', 1, 1, 1),
        (1100, NULL, N'GIP-TOTAL', 'FORMULA', NULL, 1, N'GIP_TOTAL', 1, 0, 1),
        (1110, NULL, N'Impuesto a la Renta', 'TITULO', NULL, 1, NULL, 0, 0, 1)
    ) AS f(numOrden, txtCodigo, txtRubro, codTipo, txtPrefijo, numSigno, codFormula, flgNegrita, flgResaltado, numNivel);
GO

/* -------------------------------------------------------------------------
   2. Clases de cuenta que entran al reporte
   ------------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM general.TG_CONFIGURACION WHERE txtCodigoConfiguracion = 'EJEC_PRES_CLASES_CTA')
    INSERT INTO general.TG_CONFIGURACION (txtCodigoConfiguracion, txtParametro, txtDescripcion, flgEstado, txtUsuarioCreacion)
    VALUES ('EJEC_PRES_CLASES_CTA', '67',
            'Ejecucion presupuestal: primer digito de las cuentas que entran (vacio = todas)', 1, 'SYSTEM_COSTOLABOR');
GO

/* -------------------------------------------------------------------------
   3. Reporte
   ------------------------------------------------------------------------- */

CREATE OR ALTER PROCEDURE proceso.usp_Reporte_EjecucionPresupuestal
    @numAnio int
AS
BEGIN
    SET NOCOUNT ON;

    IF @numAnio IS NULL OR @numAnio < 2000 OR @numAnio > 2100
        THROW 50181, 'El anio del reporte no es valido.', 1;

    IF DB_ID('BD_SPRING') IS NULL
        THROW 50180, 'La base de datos BD_SPRING no esta disponible: el reporte de ejecucion presupuestal sale de SPRING.', 1;

    DECLARE @anio char(4) = CAST(@numAnio AS char(4));
    DECLARE @clases varchar(20) = ISNULL((SELECT TOP (1) LTRIM(RTRIM(txtParametro))
                                          FROM general.TG_CONFIGURACION
                                          WHERE txtCodigoConfiguracion = 'EJEC_PRES_CLASES_CTA' AND flgEstado = 1), '');

    -- Montos de SPRING por mes y clasificador. Solo los codigos bien formados
    -- del clasificador: el nivel coincide con el largo del codigo ("2" nivel
    -- 1, "22" nivel 2, "22 1" nivel 3, "22 1 1" nivel 4...). Asi quedan fuera
    -- las filas de otra estructura que el maestro tambien tiene (01, 0A, 10).
    CREATE TABLE #movimiento (numMes int NOT NULL, txtClasificador varchar(50) NOT NULL, numMonto decimal(18,2) NOT NULL);

    INSERT INTO #movimiento (numMes, txtClasificador, numMonto)
    EXEC sp_executesql N'
        WITH clasificador AS (
            SELECT RTRIM(r.ReferenciaFiscal) AS codigo
            FROM BD_SPRING.dbo.AC_ReferenciaFiscal r
            WHERE r.TipoReferenciaFiscal IN (''02'', ''04'') AND r.Ano = @anio
              AND r.Version = (SELECT MAX(x.Version) FROM BD_SPRING.dbo.AC_ReferenciaFiscal x
                               WHERE x.TipoReferenciaFiscal = r.TipoReferenciaFiscal AND x.Ano = @anio)
              AND LEFT(r.ReferenciaFiscal, 1) BETWEEN ''1'' AND ''6''
              AND TRY_CAST(r.Nivel AS int) = CASE WHEN LEN(RTRIM(r.ReferenciaFiscal)) <= 2 THEN LEN(RTRIM(r.ReferenciaFiscal))
                                                  ELSE 3 + (LEN(RTRIM(r.ReferenciaFiscal)) - 4) / 2 END
            GROUP BY RTRIM(r.ReferenciaFiscal)
        )
        SELECT CAST(RIGHT(vd.period, 2) AS int), c.codigo, CAST(SUM(ISNULL(vd.localamount, 0)) AS decimal(18,2))
        FROM BD_SPRING.dbo.voucherdetail vd
        JOIN BD_SPRING.dbo.voucherheader vh ON vh.period = vd.period AND vh.voucherno = vd.voucherno
        JOIN clasificador c ON c.codigo = RTRIM(vd.ReferenciaFiscal02)
        WHERE vd.period >= @anio + ''01'' AND vd.period <= @anio + ''12''
          AND ISNULL(vh.status, '''') NOT LIKE ''%AN%''
          AND (@clases = '''' OR CHARINDEX(LEFT(LTRIM(vd.Account), 1), @clases) > 0)
        GROUP BY CAST(RIGHT(vd.period, 2) AS int), c.codigo;',
        N'@anio char(4), @clases varchar(20)', @anio = @anio, @clases = @clases;

    -- Valor de cada fila por mes. La clave es el codigo del rubro o, en las
    -- filas calculadas sin codigo, el nombre de la formula.
    CREATE TABLE #valor (txtClave varchar(30) NOT NULL, numMes int NOT NULL, numMonto decimal(18,2) NOT NULL,
                         PRIMARY KEY (txtClave, numMes));

    DECLARE @meses TABLE (numMes int PRIMARY KEY);
    INSERT INTO @meses (numMes) VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12);

    INSERT INTO #valor (txtClave, numMes, numMonto)
    SELECT r.txtCodigo, m.numMes,
           ISNULL((SELECT SUM(v.numMonto) FROM #movimiento v
                   WHERE v.numMes = m.numMes AND v.txtClasificador LIKE r.txtPrefijo + '%'), 0) * r.numSigno
    FROM proceso.TMC_EJECUCION_PRESUPUESTAL_RUBRO r
    CROSS JOIN @meses m
    WHERE r.flgEstado = 1 AND r.codTipo = 'SPRING' AND r.txtCodigo IS NOT NULL;

    -- Formulas, en orden: cada una usa las anteriores.
    DECLARE @formulas TABLE (numPaso int PRIMARY KEY, codFormula varchar(30) NOT NULL);
    INSERT INTO @formulas (numPaso, codFormula) VALUES
        (1, 'TRANSFERENCIAS_NETAS'), (2, 'RESULTADO_OPERACION'), (3, 'RESULTADO_ECONOMICO'),
        (4, 'EJERCICIOS_ANTERIORES'), (5, 'SALDO_FINAL'), (6, 'GIP_TOTAL');

    DECLARE @paso int = 1, @formula varchar(30), @clave varchar(30);
    WHILE @paso <= 6
    BEGIN
        SELECT @formula = codFormula FROM @formulas WHERE numPaso = @paso;
        -- La fila de la formula puede tener codigo (5 TRANSFERENCIAS NETAS):
        -- con el se guarda, para que las formulas siguientes la encuentren.
        SELECT @clave = COALESCE((SELECT TOP (1) txtCodigo FROM proceso.TMC_EJECUCION_PRESUPUESTAL_RUBRO
                                  WHERE codFormula = @formula AND flgEstado = 1), @formula);

        INSERT INTO #valor (txtClave, numMes, numMonto)
        SELECT @clave, m.numMes,
            CASE @formula
                WHEN 'TRANSFERENCIAS_NETAS' THEN x.v51 - x.v52
                WHEN 'RESULTADO_OPERACION'  THEN x.v1 - x.v2
                WHEN 'RESULTADO_ECONOMICO'  THEN x.vRO - x.v3 + x.v4 + x.v5
                WHEN 'EJERCICIOS_ANTERIORES' THEN CASE WHEN x.vRE + x.v6 < 0 THEN -(x.vRE + x.v6) ELSE 0 END
                WHEN 'SALDO_FINAL'          THEN x.vRE + x.v6 + x.vEA
                WHEN 'GIP_TOTAL'            THEN x.vGIP
            END
        FROM @meses m
        CROSS APPLY (
            SELECT
                SUM(CASE WHEN txtClave = '5.1' THEN numMonto ELSE 0 END) AS v51,
                SUM(CASE WHEN txtClave = '5.2' THEN numMonto ELSE 0 END) AS v52,
                SUM(CASE WHEN txtClave = '1'   THEN numMonto ELSE 0 END) AS v1,
                SUM(CASE WHEN txtClave = '2'   THEN numMonto ELSE 0 END) AS v2,
                SUM(CASE WHEN txtClave = '3'   THEN numMonto ELSE 0 END) AS v3,
                SUM(CASE WHEN txtClave = '4'   THEN numMonto ELSE 0 END) AS v4,
                SUM(CASE WHEN txtClave = '5'   THEN numMonto ELSE 0 END) AS v5,
                SUM(CASE WHEN txtClave = '6'   THEN numMonto ELSE 0 END) AS v6,
                SUM(CASE WHEN txtClave = 'RESULTADO_OPERACION'   THEN numMonto ELSE 0 END) AS vRO,
                SUM(CASE WHEN txtClave = 'RESULTADO_ECONOMICO'   THEN numMonto ELSE 0 END) AS vRE,
                SUM(CASE WHEN txtClave = 'EJERCICIOS_ANTERIORES' THEN numMonto ELSE 0 END) AS vEA,
                SUM(CASE WHEN txtClave IN ('2.2', '2.3.3', '2.3.6', '2.3.8.1', '2.3.8.2', '2.3.8.3', '2.5.2', '2.5.4.1')
                         THEN numMonto ELSE 0 END) AS vGIP
            FROM #valor
            WHERE numMes = m.numMes
        ) x
        WHERE NOT EXISTS (SELECT 1 FROM #valor y WHERE y.txtClave = @clave AND y.numMes = m.numMes);

        SET @paso += 1;
    END

    SELECT r.numOrden AS NUM_ORDEN, r.txtCodigo AS CODIGO, r.txtRubro AS RUBRO, r.codTipo AS TIPO,
           r.flgNegrita AS NEGRITA, r.flgResaltado AS RESALTADO, r.numNivel AS NIVEL,
           p.[1] AS ENERO, p.[2] AS FEBRERO, p.[3] AS MARZO, p.[4] AS ABRIL, p.[5] AS MAYO, p.[6] AS JUNIO,
           p.[7] AS JULIO, p.[8] AS AGOSTO, p.[9] AS SETIEMBRE, p.[10] AS OCTUBRE, p.[11] AS NOVIEMBRE,
           p.[12] AS DICIEMBRE,
           CASE WHEN r.codTipo = 'TITULO' THEN NULL
                ELSE ISNULL(p.[1], 0) + ISNULL(p.[2], 0) + ISNULL(p.[3], 0) + ISNULL(p.[4], 0) + ISNULL(p.[5], 0)
                   + ISNULL(p.[6], 0) + ISNULL(p.[7], 0) + ISNULL(p.[8], 0) + ISNULL(p.[9], 0) + ISNULL(p.[10], 0)
                   + ISNULL(p.[11], 0) + ISNULL(p.[12], 0) END AS TOTAL
    FROM proceso.TMC_EJECUCION_PRESUPUESTAL_RUBRO r
    LEFT JOIN (
        SELECT txtClave, [1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11], [12]
        FROM #valor
        PIVOT (SUM(numMonto) FOR numMes IN ([1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11], [12])) pv
    ) p ON p.txtClave = COALESCE(r.txtCodigo, r.codFormula) AND r.codTipo <> 'TITULO'
    WHERE r.flgEstado = 1
    ORDER BY r.numOrden;
END
GO

/* -------------------------------------------------------------------------
   4. Opcion de menu, al final de Reportes, solo para el Contador. El titulo
      REPORTES va con el perfil: sin el, el menu descarta sus opciones.
   ------------------------------------------------------------------------- */

DECLARE @usuario varchar(100) = 'SYSTEM_COSTOLABOR';

IF NOT EXISTS (SELECT 1 FROM seguridad.TG_OPCION WHERE codOpcion = 'EJECUCION_PRESUPUESTAL')
    INSERT INTO seguridad.TG_OPCION (codOpcion, nomOpcion, txtRuta, txtIcono, ideOpcionPadre, numOrden, flgEstado, txtUsuarioCreacion)
    SELECT 'EJECUCION_PRESUPUESTAL', 'Ejecución presupuestal', '/reportes/ejecucion-presupuestal', 'bi bi-journal-text',
           p.ideOpcion, ISNULL((SELECT MAX(h.numOrden) FROM seguridad.TG_OPCION h WHERE h.ideOpcionPadre = p.ideOpcion), 0) + 1,
           1, @usuario
    FROM seguridad.TG_OPCION p
    WHERE p.codOpcion = 'REPORTES';

INSERT INTO seguridad.TMD_PERFIL_OPCION (idePerfil, ideOpcion, flgEstado, txtUsuarioCreacion)
SELECT pe.idePerfil, op.ideOpcion, 1, @usuario
FROM (VALUES ('REPORTES'), ('EJECUCION_PRESUPUESTAL')) AS r(codOpcion)
JOIN seguridad.TMC_PERFIL pe ON pe.codPerfil = 'CONTADOR'
JOIN seguridad.TG_OPCION  op ON op.codOpcion = r.codOpcion
WHERE NOT EXISTS (SELECT 1 FROM seguridad.TMD_PERFIL_OPCION po
                  WHERE po.idePerfil = pe.idePerfil AND po.ideOpcion = op.ideOpcion);
GO
