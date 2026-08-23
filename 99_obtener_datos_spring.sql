--  1° Ejecuta ExtraerDatosDeSQL() del Módulo3
--  2° Ejecuta QuitarEspacio() del Módulo5
--  3° Ejecuta CategorizarDatos() del Módulo1
--  4° Ejecuta ActualizarTabla() del Módulo15
--  5° Ejecuta CategorizarProyectos() del Módulo10
--  6° Ejecuta ActualizarTabla2() del Módulo16

-- (1°)
-- Configurar la primera consulta SQL
-- Insertamos en tabla proceso.TMD_GASTO_PERSONAL (BD_REP19) 
SELECT vd.voucherno, '' as txtTipoGasto, vd.voucherline, vd.vendor, vh.status, TRIM(am.localname) AS txtLocalName, 
           vd.localamount,pm.Persona as idePersona, TRIM(pm.NombreCompleto) AS txtNombreCompleto, am.account
           , pm.Documento, hrdiv.DescripcionLarga AS Area, hrdep.Descripcion as Departamento, 
           hre.Descripcion AS Cargo, 
           vd.CostCenter, em.CentroCostos, vd.period 
           FROM voucherdetail AS vd 
           LEFT JOIN PersonaMast AS pm ON vd.vendor = pm.Persona 
           LEFT JOIN EmpleadoMast AS em ON pm.Persona = em.Empleado 
           LEFT JOIN HR_PuestoEmpresa hre ON hre.CodigoPuesto = em.CodigoCargo 
           LEFT JOIN HR_Departamento hrdep ON em.DepartamentoOperacional = hrdep.Departamento 
           LEFT JOIN HR_Division as hrdiv ON em.Division=hrdiv.Division 
           LEFT JOIN voucherheader AS vh ON vh.period = vd.period AND vh.voucherno = vd.voucherno 
           LEFT JOIN accountmst AS am ON am.account = vd.Account 
           WHERE vd.period = '202501' AND vh.status = 'PR' 
           AND am.account BETWEEN 62110010 AND 65990070 
           AND am.account NOT IN (63801400, 63801410, 63801420, 63801430, 63801440, 63801450, 63801460, 63801470, 63801480, 63801490, 63801500, 63801600, 63802070, 63802080, 63802085, 63802090, 63802095, 63803000, 63803005, 63803010, 63930040) 
           AND vd.afe Not in ('000000505049')
           AND NOT (vd.CostCenter = '0216')

-- (2°) --Aplicar un Trim a account,CostCenter, CentroCostos, Departamento (En general a todos los textos para asegurar que los datos no tienen espacios vacios demás)

-- (3°) -- Genera una columna Tipo de Gasto y según el case de la celda account llena los valores
/*
    Select Case ws.Cells(i, 8).Value ' Columna Q es la 17

                Case "63630010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63140010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63130010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63520010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63560010": ws.Cells(i, 2).Value = "Gasto Operativo"
                
                Case "64320010": ws.Cells(i, 2).Value = "Gasto Operativo"
                    If ws.Cells(i, 13).Value = "111" Then
                        ws.Cells(i, 2).Value = "Reembolso y Proinv."
                    Else
                        ws.Cells(i, 2).Value = "Gasto Operativo"
                    End If
                
                
                Case "63210010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63220010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62200010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "62200010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "63230010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63670010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62500020": ws.Cells(i, 2).Value = "Bonos y Otros"
                Case "62400010": ws.Cells(i, 2).Value = "Bonos y Otros"
                Case "62500030": ws.Cells(i, 2).Value = "Bonos y Otros"
                Case "63802050": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62910010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "65600060": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65600050": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63120010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65990050": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63710020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63610010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65600070": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63710030": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62500050": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "63802010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63910010": ws.Cells(i, 2).Value = "Gastos Financiero"
                Case "65990020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62500040": ws.Cells(i, 2).Value = "Gasto Operativo"
                
                Case "65990070"
                    If ws.Cells(i, 13).Value = "111" Then
                        ws.Cells(i, 2).Value = "Reembolso y Proinv."
                    Else
                        ws.Cells(i, 2).Value = "Gasto Operativo"
                    End If
                
                Case "62140010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "64120010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64110010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63650010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63430020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63430030": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63430010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63440010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65600020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63802030": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63290010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65990060": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63290020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63150010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63430040": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65100070": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63802060": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62200030": ws.Cells(i, 2).Value = "Bonos y Otros"
                Case "62710010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "62800010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62730010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62740010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65100040": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65100050": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62750010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "65100030": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62500031": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "63802020": ws.Cells(i, 2).Value = "Gasto Operativo"
                
                Case "63112040"
                    If ws.Cells(i, 13).Value = "111" Then
                        ws.Cells(i, 2).Value = "Reembolso y Proinv."
                    Else
                        ws.Cells(i, 2).Value = "Gasto Operativo"
                    End If
                
                Case "64310010"
                    If ws.Cells(i, 13).Value = "111" Then
                        ws.Cells(i, 2).Value = "Reembolso y Proinv."
                    Else
                        ws.Cells(i, 2).Value = "Gasto Operativo"
                    End If
                
                
                Case "63801030": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63801060": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63801090": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63801040": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63801050": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63801010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63801070": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63930060": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63801080": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62110010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "65600080": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65300010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63640010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63640020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63112020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63111010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63112030": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63112010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62200020": ws.Cells(i, 2).Value = "Bonos y Otros"
                Case "65600010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "62150010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "62120010": ws.Cells(i, 2).Value = "Gasto de Personal"


                Case "62130010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "62200040": ws.Cells(i, 2).Value = "Bonos y Otros"
                Case "62200050": ws.Cells(i, 2).Value = "Bonos y Otros"
                Case "62300010": ws.Cells(i, 2).Value = "Bonos y Otros"
                Case "62500010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "62600010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "62720010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "62920010": ws.Cells(i, 2).Value = "Gasto de Personal"
                Case "62930010": ws.Cells(i, 2).Value = "Bonos y Otros"
                Case "63112040": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63112050": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63210020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63220020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63230020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63230030": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63240010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63240020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63250010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63250020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63260010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63260020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63270010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63270020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63300010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63410010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63420010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63422010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63450010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63510010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63530010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63540010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63620010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63660010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63710010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63720010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63730010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63801020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63802040": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63803020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63803030": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63803040": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63920010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63930020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63930040": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63930050": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "63930090": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64130010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64140010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64150010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64160010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64190010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64190020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64200010": ws.Cells(i, 2).Value = "Gasto Operativo"
                
                Case "64330010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64340010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64390010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64410010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64420010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "64430010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65100010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65100020": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65100060": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65200010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65400010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65514030": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65600030": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65600031": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65600040": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65600090": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65800010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65910010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65990010": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65990030": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65990040": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65990070": ws.Cells(i, 2).Value = "Gasto Operativo"
                Case "65990080": ws.Cells(i, 2).Value = "Gasto Operativo"


                Case "65514060": ws.Cells(i, 2).Value = "Otros"
                Case "65514050": ws.Cells(i, 2).Value = "Otros"


            Case Else
                ws.Cells(i, 2).Value = "Categoría Desconocida"
        End Select
    Next i
        ' Añadir encabezado para la nueva columna
    ws.Cells(1, 2).Value = "Tipo de Gasto" ' Columna B (2) para la nueva columna
*/
-- (4°) Pivotea la tabla BD_REP19 y genera el resumen prueba_Gasto personal

-- (5°) 

-- Configurar la segunda consulta SQL
-- Insertamos en tabla proceso.TMD_DISTRIBUCION_COMPENSACION (BD_DistribucionCompensa)
SELECT vdet.period, ACREF.DescripcionLocal, vDet.afe as Proyecto, 
           vDet.localamount as Monto, a.englishname, '' as txtCategoria, vDet.Account, vDet.voucherno, vDet.vendor, vDet.invoice 
           FROM voucherdetail as vDet 
           LEFT JOIN AC_ReferenciaFiscal as AcRef ON vDet.ReferenciaFiscal03 = AcRef.ReferenciaFiscal 
           LEFT JOIN voucherheader as vh ON vh.period = vDet.period AND vh.voucherno = vDet.voucherno 
           LEFT JOIN afemst as a ON a.afe = vDet.afe  
           LEFT JOIN accountmst as am ON am.account = vDet.Account 
           WHERE AcRef.Ano = '2025' 
           AND vDet.period = '202501' 
           AND AcRef.TipoReferenciaFiscal = '03' 
           AND AcRef.Version = '1' 
           AND vDet.ReferenciaFiscal02 = '33 1 1 1 1' 
           AND vdet.afe IS NOT NULL 
           AND vDet.afe <> '000000000074' 
           AND vh.status NOT LIKE '%AN%' 
           AND AcRef.DescripcionLocal NOT LIKE '%PRESUPUESTO OPERATIVO%'

-- En la tabla BD_DistribucionCompensa categoriza los valores segúnn la celda proyecto
/*
    Select Case ws.Cells(i, 3).Value ' Columna H es la 8

            Case "000000000001   ", "000000000007   ", "000000000009   ", "000000000013   ", _
                 "000000000027   ", "000000000029   ", "000000000040   ", "000000000041   ", _
                 "000000000057   ", "000000000058   ", "000000000065   ", "000000000104   ", _
                 "000000202009   ", "000000203008   ", "000000210033   ", "000000210034   ", _
                 "000000210035   ", "000000210045   ", "000000220014   ", "000000220017   ", _
                 "000000230073   ":
                ws.Cells(i, 6).Value = "FA"
            
            Case "000000000018   ", "000000000019   ", "000000000020   ", "000000000021   ", _
                 "000000000022   ", "000000000023   ", "000000321016   ", "000000000103   ", _
                 "000000210043   ", "000000302002   ", "000000302004   ", "000000302006   ", _
                 "000000302007   ", "000000310031   ", "000000310032   ", "000000321001   ", _
                 "000000340001   ", "000000340002   ", "000000350001   ", "000000364001   ", _
                 "000000632025   ", "000000632026   ":
                ws.Cells(i, 6).Value = "PAR"
            
            Case "000000000074   ":
                ws.Cells(i, 6).Value = "TUCARI"
            
            Case "000000000105   ", "000000000106   ", "000000000107   ":
                ws.Cells(i, 6).Value = "TUQUIAR"
            
            Case Else:
                ws.Cells(i, 6).Value = "Categoría Desconocida"
        End Select
    Next i
        ' Añadir encabezado para la nueva columna
    ws.Cells(1, 6).Value = "Categoria" ' Columna B (2) para la nueva columna
*/

-- (6°) Pivotea la tabla BD_DistribucionCompensa y genera el resumen TD_DistribucionCompensa