SET SERVEROUTPUT ON;

-- ============================================================
-- ACTIVIDAD SEMANA 2 - PRY2206
-- Incorporando sentencias DML y estructuras de iteración
-- Caso LOGi & CARG
-- Autor: Angelo Silva
-- ============================================================

-- Variables BIND solicitadas para el proceso
VARIABLE b_periodo VARCHAR2(10);
VARIABLE b_mes_proceso VARCHAR2(2);

-- Se asigna dinámicamente el periodo según la fecha de ejecución
BEGIN
    :b_periodo := TO_CHAR(SYSDATE, 'MMYYYY');
    :b_mes_proceso := TO_CHAR(SYSDATE, 'MM');
END;
/


TRUNCATE TABLE DETALLE_DE_CLIENTES;

DECLARE
    -- Variables escalares usando %TYPE
    v_idc              DETALLE_DE_CLIENTES.IDC%TYPE;
    v_rut              DETALLE_DE_CLIENTES.RUT%TYPE;
    v_cliente          DETALLE_DE_CLIENTES.CLIENTE%TYPE;
    v_edad             DETALLE_DE_CLIENTES.EDAD%TYPE;
    v_puntaje          DETALLE_DE_CLIENTES.PUNTAJE%TYPE;
    v_correo           DETALLE_DE_CLIENTES.CORREO_CORP%TYPE;
    v_periodo          DETALLE_DE_CLIENTES.PERIODO%TYPE;

    v_nombre_comuna    COMUNA.NOMBRE_COMUNA%TYPE;
    v_tipo_cliente     TIPO_CLIENTE.NOMBRE_TIPO_CLI%TYPE;
    v_porcentaje       TRAMO_EDAD.PORCENTAJE%TYPE;
    v_anno_proceso     TRAMO_EDAD.ANNO_VIG%TYPE;

    -- Contadores para validar que se procesaron todos los clientes
    v_total_clientes   NUMBER := 0;
    v_contador         NUMBER := 0;

BEGIN
    -- Se obtiene el total de clientes existentes para validar el proceso al final.
    SELECT COUNT(*)
    INTO v_total_clientes
    FROM CLIENTE;

    -- Año de ejecución del proceso, usado para buscar el tramo de edad vigente.
    v_anno_proceso := TO_NUMBER(TO_CHAR(SYSDATE, 'YYYY'));

    -- Ciclo que procesa todos los clientes uno a uno.
    FOR reg_cliente IN (
        SELECT 
            c.ID_CLI,
            c.NUMRUN_CLI,
            c.DVRUN_CLI,
            c.APPATERNO_CLI,
            c.APMATERNO_CLI,
            c.PNOMBRE_CLI,
            c.SNOMBRE_CLI,
            c.RENTA,
            c.FECHA_NAC_CLI,
            co.NOMBRE_COMUNA,
            tc.NOMBRE_TIPO_CLI
        FROM CLIENTE c
        LEFT JOIN COMUNA co
            ON c.ID_COMUNA = co.ID_COMUNA
        INNER JOIN TIPO_CLIENTE tc
            ON c.ID_TIPO_CLI = tc.ID_TIPO_CLI
        ORDER BY c.ID_CLI
    ) LOOP

        -- Inicialización de variables por cada iteración
        v_idc := reg_cliente.ID_CLI;
        v_rut := reg_cliente.NUMRUN_CLI;
        v_nombre_comuna := reg_cliente.NOMBRE_COMUNA;
        v_tipo_cliente := reg_cliente.NOMBRE_TIPO_CLI;
        v_periodo := :b_periodo;
        v_puntaje := 0;

        -- Cálculo dinámico de edad según la fecha actual.
        v_edad := FLOOR(MONTHS_BETWEEN(SYSDATE, reg_cliente.FECHA_NAC_CLI) / 12);

        -- Nombre completo del cliente para insertar en la tabla de detalle.
        v_cliente := INITCAP(
            reg_cliente.PNOMBRE_CLI || ' ' ||
            NVL(reg_cliente.SNOMBRE_CLI || ' ', '') ||
            reg_cliente.APPATERNO_CLI || ' ' ||
            reg_cliente.APMATERNO_CLI
        );

        -- Regla B:
        -- Si la renta es superior a 800.000 y no vive en La Reina, Las Condes o Vitacura,
        -- obtiene el 3% de la renta como puntaje.
        IF reg_cliente.RENTA > 800000
           AND UPPER(v_nombre_comuna) NOT IN ('LA REINA', 'LAS CONDES', 'VITACURA') THEN

            v_puntaje := ROUND(reg_cliente.RENTA * 0.03);

        -- Regla C:
        -- Si no cumple la regla anterior, recibe 30 puntos por cada año de edad,
        -- siempre que sea cliente VIP, Internacional o Extranjero.
        ELSIF UPPER(v_tipo_cliente) IN ('VIP', 'INTERNACIONAL', 'EXTRANJERO') THEN

            v_puntaje := ROUND(v_edad * 30);

        END IF;

        -- Regla D:
        -- Si el puntaje sigue siendo 0, se busca el porcentaje en TRAMO_EDAD
        -- según edad y año de vigencia del proceso.
        IF v_puntaje = 0 THEN
            BEGIN
                SELECT PORCENTAJE
                INTO v_porcentaje
                FROM TRAMO_EDAD
                WHERE ANNO_VIG = v_anno_proceso
                  AND v_edad BETWEEN TRAMO_INF AND TRAMO_SUP;

                v_puntaje := ROUND(reg_cliente.RENTA * (v_porcentaje / 100));

            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_puntaje := 0;
            END;
        END IF;

        -- Generación del correo corporativo simulado del cliente.
        v_correo := LOWER(reg_cliente.APPATERNO_CLI) ||
                    v_edad ||
                    '*' ||
                    SUBSTR(reg_cliente.PNOMBRE_CLI, 1, 1) ||
                    TO_CHAR(reg_cliente.FECHA_NAC_CLI, 'DD') ||
                    :b_mes_proceso ||
                    '@LogiCarg.cl';

        -- Sentencia DML que inserta el resultado del proceso en la tabla solicitada.
        INSERT INTO DETALLE_DE_CLIENTES (
            IDC,
            RUT,
            CLIENTE,
            EDAD,
            PUNTAJE,
            CORREO_CORP,
            PERIODO
        ) VALUES (
            v_idc,
            v_rut,
            v_cliente,
            v_edad,
            v_puntaje,
            v_correo,
            v_periodo
        );

        -- Contador de clientes procesados.
        v_contador := v_contador + 1;

    END LOOP;

    -- Validación final: si se procesaron todos los clientes, confirma cambios.
    -- Si no coinciden los contadores, se deshacen las transacciones.
    IF v_contador = v_total_clientes THEN
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Proceso finalizado correctamente.');
        DBMS_OUTPUT.PUT_LINE('Total de clientes procesados: ' || v_contador);
    ELSE
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Proceso finalizado con errores.');
        DBMS_OUTPUT.PUT_LINE('Se realizó ROLLBACK porque no se procesaron todos los clientes.');
        DBMS_OUTPUT.PUT_LINE('Clientes esperados: ' || v_total_clientes);
        DBMS_OUTPUT.PUT_LINE('Clientes procesados: ' || v_contador);
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error durante la ejecución del proceso.');
        DBMS_OUTPUT.PUT_LINE('Se realizó ROLLBACK.');
        DBMS_OUTPUT.PUT_LINE('Detalle del error: ' || SQLERRM);
END;
/

-- Consulta final para revisar el informe generado.
SELECT *
FROM DETALLE_DE_CLIENTES
ORDER BY IDC;