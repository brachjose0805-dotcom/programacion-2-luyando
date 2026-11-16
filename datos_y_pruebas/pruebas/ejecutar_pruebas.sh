#!/bin/bash
# Ejecuta todos los casos de uso y genera los archivos salida_*.txt
# Uso (desde la carpeta del proyecto):
#     g++ -std=c++17 -Wall -o taller taller.cpp
#     bash pruebas/ejecutar_pruebas.sh
# Cada caso se ejecuta en una carpeta de trabajo propia (pruebas/trabajo/casoN),
# asi no se modifica la carpeta datos/ pre-poblada.

RAIZ=$(cd "$(dirname "$0")/.." && pwd)
TALLER="$RAIZ/taller"
P="$RAIZ/pruebas"
TRABAJO="$P/trabajo"
rm -rf "$TRABAJO"
mkdir -p "$TRABAJO"

vacio()   { mkdir -p "$TRABAJO/caso$1"; }                                         # caso que empieza sin datos
poblado() { mkdir -p "$TRABAJO/caso$1"; cp -r "$RAIZ/datos" "$TRABAJO/caso$1/datos"; }  # caso con datos/ pre-poblados
correr()  { ( cd "$TRABAJO/caso$1" && "$TALLER" --eco < "$P/entrada_$1$2.txt" > "$P/salida_$1$2.txt" ); echo "caso $1$2 listo"; }

vacio 1;    correr 1 a; correr 1 b                    # 1: persistencia entre ejecuciones
vacio 2;    correr 2 a                                # 2: acceso directo por ID
poblado 3;  correr 3 a; correr 3 b; correr 3 c        # 3: la orden sobrevive con su detalle
poblado 4;  correr 4 a; correr 4 b                    # 4: orden con 15 lineas
poblado 5;  correr 5 a; correr 5 b                    # 5: anulacion con reversion en disco
poblado 6;  correr 6 a                                # 6: baja de mecanico e historial
poblado 7;  correr 7 a                                # 7: integridad tras restauracion parcial
# Paso manual del caso 7: reemplazar datos/vehiculos.bin por la copia del backup
cp "$TRABAJO"/caso7/backup_*/vehiculos.bin "$TRABAJO/caso7/datos/vehiculos.bin"
correr 7 b
poblado 8;  correr 8 a                                # 8: reportes
poblado 9;  correr 9 a                                # extra: validaciones y errores
poblado 10; correr 10 a                               # extra: limite de lineas
rm -rf "$TRABAJO"
