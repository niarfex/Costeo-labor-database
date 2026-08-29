/* =========================================================================
   19 - La jefatura no valida sus propias horas (HU-005)

   Se rehace usp_RegistroHoraDia_Validar agregando el error 50017: el empleado
   que se valida no puede ser el mismo que resuelve el usuario del token.
   ========================================================================= */

USE COSTO_LABOR;
GO

CREATE OR ALTER PROCEDURE registro.usp_RegistroHoraDia_Validar
    @ideEmpleado    bigint,
    @fecLabor       date,
    @flgConforme    int,
    @txtComentario  varchar(250) = NULL,
    @txtUsuario     varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    IF @flgConforme = 0 AND (@txtComentario IS NULL OR LTRIM(RTRIM(@txtComentario)) = '')
        THROW 50015, 'Observar un registro exige ingresar un comentario.', 1;

    IF NOT EXISTS (SELECT 1 FROM registro.TMD_REGISTRO_HORADIA
                   WHERE ideEmpleado = @ideEmpleado AND fecLabor = @fecLabor AND flgEstado = 1)
        THROW 50013, 'No existen horas registradas para la fecha indicada.', 1;

    -- Nadie da conformidad a sus propias horas, aunque tenga perfil de jefatura.
    IF @ideEmpleado = (SELECT TOP (1) pu.ideEmpleado
                       FROM seguridad.TMD_PERFIL_USUARIO pu
                       WHERE pu.txtUsuario = @txtUsuario
                         AND pu.ideEmpleado IS NOT NULL
                         AND pu.flgEstado = 1)
        THROW 50017, 'No puede validar sus propias horas registradas.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO registro.TMD_REGISTRO_HORADIA_VALIDACION
              (ideRegistroHoradia, flgConforme, flgSubsanado, txtComentario, txtUsuarioCreacion)
        SELECT r.ideRegistroHoradia,
               @flgConforme,
               CASE WHEN @flgConforme = 0 THEN 0 ELSE NULL END,
               @txtComentario,
               @txtUsuario
        FROM registro.TMD_REGISTRO_HORADIA r
        WHERE r.ideEmpleado = @ideEmpleado AND r.fecLabor = @fecLabor AND r.flgEstado = 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
