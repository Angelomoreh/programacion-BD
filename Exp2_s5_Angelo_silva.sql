SET SERVEROUTPUT ON;

-- PROGRAMACION DE BASES DE DATOS - PRY2206
-- EXPERIENCIA 2 - SEMANA 5
-- Manejo de excepciones en un bloque PL/SQL anonimo complejo
-- Estudiante: Angelo silva


-- La fecha se ingresa con formato MMYYYY.
VARIABLE b_fecha_proceso VARCHAR2(6);
VARIABLE b_limite_asignacion NUMBER;

BEGIN
    :b_fecha_proceso := '062021';
    :b_limite_asignacion := 250000;
END;
/

-- Las tablas de resultado se limpian antes de cada ejecucion.
TRUNCATE TABLE detalle_asignacion_mes;
TRUNCATE TABLE resumen_mes_profesion;
TRUNCATE TABLE errores_proceso;

-- La secuencia se elimina y vuelve a crear en tiempo de ejecucion.
DROP SEQUENCE sq_error;
CREATE SEQUENCE sq_error
    START WITH 1
    INCREMENT BY 1
    NOCACHE;

DECLARE
    -- VARRAY con los porcentajes de movilizacion extra:
    -- Santiago, Nunoa, La Reina, La Florida y Macul.
    TYPE t_porcentajes_movil IS VARRAY(5) OF NUMBER;
    v_porcentajes_movil t_porcentajes_movil :=
        t_porcentajes_movil(2, 4, 5, 7, 9);

    -- Registro que almacena los datos basicos de cada profesional.
    TYPE t_reg_profesional IS RECORD (
        numrun_prof       profesional.numrun_prof%TYPE,
        dvrun_prof        profesional.dvrun_prof%TYPE,
        appaterno         profesional.appaterno%TYPE,
        nombre            profesional.nombre%TYPE,
        sueldo            profesional.sueldo%TYPE,
        cod_comuna        profesional.cod_comuna%TYPE,
        cod_profesion     profesional.cod_profesion%TYPE,
        cod_tpcontrato    profesional.cod_tpcontrato%TYPE,
        nombre_profesion  profesion.nombre_profesion%TYPE
    );

    v_profesional t_reg_profesional;

    -- Cursor sin parametro. Obtiene solamente los datos basicos
    -- requeridos para los calculos y el informe de detalle.
    CURSOR c_profesionales IS
        SELECT p.numrun_prof,
               p.dvrun_prof,
               p.appaterno,
               p.nombre,
               p.sueldo,
               p.cod_comuna,
               p.cod_profesion,
               p.cod_tpcontrato,
               pr.nombre_profesion
          FROM profesional p
          JOIN profesion pr
            ON pr.cod_profesion = p.cod_profesion
         WHERE EXISTS (
                   SELECT 1
                     FROM asesoria a
                    WHERE a.numrun_prof = p.numrun_prof
                      AND a.inicio_asesoria >=
                          TO_DATE(:b_fecha_proceso, 'MMYYYY')
                      AND a.inicio_asesoria <
                          ADD_MONTHS(
                              TO_DATE(:b_fecha_proceso, 'MMYYYY'),
                              1
                          )
               )
         ORDER BY pr.nombre_profesion, p.appaterno, p.nombre;

    -- Cursor con parametro. Obtiene por separado la cantidad de
    -- asesorias y la suma de honorarios del profesional procesado.
    CURSOR c_asesorias (
        p_numrun profesional.numrun_prof%TYPE
    ) IS
        SELECT COUNT(*),
               NVL(SUM(a.honorario), 0)
          FROM asesoria a
         WHERE a.numrun_prof = p_numrun
           AND a.inicio_asesoria >=
               TO_DATE(:b_fecha_proceso, 'MMYYYY')
           AND a.inicio_asesoria <
               ADD_MONTHS(
                   TO_DATE(:b_fecha_proceso, 'MMYYYY'),
                   1
               );

    -- Cursor para generar el resumen ordenado por profesion.
    CURSOR c_profesiones_resumen IS
        SELECT DISTINCT profesion
          FROM detalle_asignacion_mes
         ORDER BY profesion;

    -- Excepcion definida por el usuario para controlar el limite.
    e_tope_superado EXCEPTION;

    v_mes_proceso          NUMBER(2);
    v_anno_proceso         NUMBER(4);
    v_anno_mes_proceso     NUMBER(6);
    v_nro_asesorias        NUMBER(3);
    v_monto_honorarios     NUMBER(8);
    v_porcentaje_contrato  tipo_contrato.incentivo%TYPE;
    v_porcentaje_profesion porcentaje_profesion.asignacion%TYPE;
    v_monto_movil_extra    NUMBER(8);
    v_monto_asig_tipocont  NUMBER(8);
    v_monto_asig_profesion NUMBER(8);
    v_total_asignaciones   NUMBER(8);
    v_total_sin_tope       NUMBER(8);
    v_error_oracle         errores_proceso.mensaje_error_oracle%TYPE;
    v_cantidad_procesada   NUMBER := 0;

    v_total_asesorias      NUMBER(4);
    v_total_honorarios     NUMBER(8);
    v_total_movil_extra    NUMBER(8);
    v_total_asig_tipocont  NUMBER(8);
    v_total_asig_prof      NUMBER(8);
    v_total_general        NUMBER(8);

BEGIN
    -- El mes, ano y periodo se obtienen desde la variable BIND.
    v_mes_proceso := TO_NUMBER(
        TO_CHAR(TO_DATE(:b_fecha_proceso, 'MMYYYY'), 'MM')
    );
    v_anno_proceso := TO_NUMBER(
        TO_CHAR(TO_DATE(:b_fecha_proceso, 'MMYYYY'), 'YYYY')
    );
    v_anno_mes_proceso := v_anno_proceso * 100 + v_mes_proceso;

    OPEN c_profesionales;
    LOOP
        FETCH c_profesionales INTO v_profesional;
        EXIT WHEN c_profesionales%NOTFOUND;

        -- Inicializacion de montos para el profesional actual.
        v_nro_asesorias := 0;
        v_monto_honorarios := 0;
        v_monto_movil_extra := 0;
        v_monto_asig_tipocont := 0;
        v_monto_asig_profesion := 0;
        v_total_asignaciones := 0;

        -- El cursor parametrizado calcula cantidad y honorarios.
        OPEN c_asesorias(v_profesional.numrun_prof);
        FETCH c_asesorias
         INTO v_nro_asesorias, v_monto_honorarios;
        CLOSE c_asesorias;

        -- Calculo PL/SQL de movilizacion segun comuna y honorarios.
        CASE v_profesional.cod_comuna
            WHEN 82 THEN
                IF v_monto_honorarios < 350000 THEN
                    v_monto_movil_extra :=
                        ROUND(v_monto_honorarios *
                              v_porcentajes_movil(1) / 100);
                END IF;
            WHEN 83 THEN
                v_monto_movil_extra :=
                    ROUND(v_monto_honorarios *
                          v_porcentajes_movil(2) / 100);
            WHEN 85 THEN
                IF v_monto_honorarios < 400000 THEN
                    v_monto_movil_extra :=
                        ROUND(v_monto_honorarios *
                              v_porcentajes_movil(3) / 100);
                END IF;
            WHEN 86 THEN
                IF v_monto_honorarios < 800000 THEN
                    v_monto_movil_extra :=
                        ROUND(v_monto_honorarios *
                              v_porcentajes_movil(4) / 100);
                END IF;
            WHEN 89 THEN
                IF v_monto_honorarios < 680000 THEN
                    v_monto_movil_extra :=
                        ROUND(v_monto_honorarios *
                              v_porcentajes_movil(5) / 100);
                END IF;
            ELSE
                v_monto_movil_extra := 0;
        END CASE;

        -- El porcentaje por tipo de contrato se obtiene por separado.
        SELECT incentivo
          INTO v_porcentaje_contrato
          FROM tipo_contrato
         WHERE cod_tpcontrato = v_profesional.cod_tpcontrato;

        v_monto_asig_tipocont :=
            ROUND(v_monto_honorarios * v_porcentaje_contrato / 100);

        -- Bloque anidado que controla cualquier error Oracle al
        -- recuperar el porcentaje asociado a la profesion.
        BEGIN
            SELECT asignacion
              INTO v_porcentaje_profesion
              FROM porcentaje_profesion
             WHERE cod_profesion = v_profesional.cod_profesion;

            v_monto_asig_profesion :=
                ROUND(v_profesional.sueldo *
                      v_porcentaje_profesion / 100);
        EXCEPTION
            WHEN OTHERS THEN
                v_error_oracle := SQLERRM;

                INSERT INTO errores_proceso (
                    error_id,
                    mensaje_error_oracle,
                    mensaje_error_usr
                ) VALUES (
                    sq_error.NEXTVAL,
                    v_error_oracle,
                    'Error al obtener porcentaje de asignacion para ' ||
                    'el run Nro. ' || v_profesional.numrun_prof
                );

                v_monto_asig_profesion := 0;
        END;

        -- El total corresponde a la suma de las tres asignaciones.
        v_total_asignaciones :=
            v_monto_movil_extra +
            v_monto_asig_tipocont +
            v_monto_asig_profesion;

        -- Excepcion de usuario para reemplazar totales que superan
        -- el limite definido por la empresa.
        BEGIN
            IF v_total_asignaciones > :b_limite_asignacion THEN
                v_total_sin_tope := v_total_asignaciones;
                RAISE e_tope_superado;
            END IF;
        EXCEPTION
            WHEN e_tope_superado THEN
                INSERT INTO errores_proceso (
                    error_id,
                    mensaje_error_oracle,
                    mensaje_error_usr
                ) VALUES (
                    sq_error.NEXTVAL,
                    'TOPE_SUPERADO',
                    'Se reemplazo el monto total de las asignaciones ' ||
                    'calculadas de ' || v_total_sin_tope ||
                    ' por el monto limite de ' ||
                    :b_limite_asignacion || ' para el run Nro. ' ||
                    v_profesional.numrun_prof
                );

                v_total_asignaciones := :b_limite_asignacion;
        END;

        -- Insercion del informe de detalle.
        INSERT INTO detalle_asignacion_mes (
            mes_proceso,
            anno_proceso,
            run_profesional,
            nombre_profesional,
            profesion,
            nro_asesorias,
            monto_honorarios,
            monto_movil_extra,
            monto_asig_tipocont,
            monto_asig_profesion,
            monto_total_asignaciones
        ) VALUES (
            v_mes_proceso,
            v_anno_proceso,
            TO_CHAR(v_profesional.numrun_prof),
            v_profesional.appaterno || ' ' || v_profesional.nombre,
            v_profesional.nombre_profesion,
            v_nro_asesorias,
            v_monto_honorarios,
            v_monto_movil_extra,
            v_monto_asig_tipocont,
            v_monto_asig_profesion,
            v_total_asignaciones
        );

        v_cantidad_procesada := v_cantidad_procesada + 1;
    END LOOP;
    CLOSE c_profesionales;

    -- Generacion del resumen. Las funciones de grupo se ejecutan
    -- en una sentencia SELECT separada para cada profesion.
    FOR r_profesion IN c_profesiones_resumen LOOP
        SELECT NVL(SUM(nro_asesorias), 0),
               NVL(SUM(monto_honorarios), 0),
               NVL(SUM(monto_movil_extra), 0),
               NVL(SUM(monto_asig_tipocont), 0),
               NVL(SUM(monto_asig_profesion), 0),
               NVL(SUM(monto_total_asignaciones), 0)
          INTO v_total_asesorias,
               v_total_honorarios,
               v_total_movil_extra,
               v_total_asig_tipocont,
               v_total_asig_prof,
               v_total_general
          FROM detalle_asignacion_mes
         WHERE profesion = r_profesion.profesion;

        INSERT INTO resumen_mes_profesion (
            anno_mes_proceso,
            profesion,
            total_asesorias,
            monto_total_honorarios,
            monto_total_movil_extra,
            monto_total_asig_tipocont,
            monto_total_asig_prof,
            monto_total_asignaciones
        ) VALUES (
            v_anno_mes_proceso,
            r_profesion.profesion,
            v_total_asesorias,
            v_total_honorarios,
            v_total_movil_extra,
            v_total_asig_tipocont,
            v_total_asig_prof,
            v_total_general
        );
    END LOOP;

    -- Las transacciones se confirman solo si finaliza todo el proceso.
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Proceso finalizado correctamente.');
    DBMS_OUTPUT.PUT_LINE(
        'Profesionales procesados: ' || v_cantidad_procesada
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Ante un error no controlado se deshace toda la transaccion.
        IF c_asesorias%ISOPEN THEN
            CLOSE c_asesorias;
        END IF;

        IF c_profesionales%ISOPEN THEN
            CLOSE c_profesionales;
        END IF;

        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('El proceso fue cancelado.');
        DBMS_OUTPUT.PUT_LINE('Error Oracle: ' || SQLERRM);
        RAISE;
END;
/

-- Consultas de comprobacion de los tres informes generados.
SELECT *
  FROM detalle_asignacion_mes
 ORDER BY profesion, nombre_profesional;

SELECT *
  FROM resumen_mes_profesion
 ORDER BY profesion;

SELECT *
  FROM errores_proceso
 ORDER BY error_id;