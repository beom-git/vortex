// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`ifndef DPI_FLOAT_VH
`define DPI_FLOAT_VH

import "DPI-C" function void dpi_fadd(input bit enable, input int dst_fmt, input longint a, input longint b, input bit[2:0] frm, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_fsub(input bit enable, input int dst_fmt, input longint a, input longint b, input bit[2:0] frm, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_fmul(input bit enable, input int dst_fmt, input longint a, input longint b, input bit[2:0] frm, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_fmadd(input bit enable, input int dst_fmt, input longint a, input longint b, input longint c, input bit[2:0] frm, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_fmsub(input bit enable, input int dst_fmt, input longint a, input longint b, input longint c, input bit[2:0] frm, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_fnmadd(input bit enable, input int dst_fmt, input longint a, input longint b, input longint c, input bit[2:0] frm, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_fnmsub(input bit enable, input int dst_fmt, input longint a, input longint b, input longint c, input bit[2:0] frm, output longint result, output bit[4:0] fflags);

import "DPI-C" function void dpi_fdiv(input bit enable, input int dst_fmt, input longint a, input longint b, input bit[2:0] frm, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_fsqrt(input bit enable, input int dst_fmt, input longint a, input bit[2:0] frm, output longint result, output bit[4:0] fflags);

import "DPI-C" function void dpi_ftoi(input bit enable, input int dst_fmt, input int src_fmt, input longint a, input bit[2:0] frm, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_ftou(input bit enable, input int dst_fmt, input int src_fmt, input longint a, input bit[2:0] frm, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_itof(input bit enable, input int dst_fmt, input int src_fmt, input longint a, input bit[2:0] frm, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_utof(input bit enable, input int dst_fmt, input int src_fmt, input longint a, input bit[2:0] frm, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_f2f(input bit enable, input int dst_fmt, input int src_fmt, input longint a, input bit[2:0] frm, output longint result, output bit[4:0] fflags);

import "DPI-C" function void dpi_fclss(input bit enable, input int dst_fmt, input longint a, output longint result);
import "DPI-C" function void dpi_fsgnj(input bit enable, input int dst_fmt, input longint a, input longint b, output longint result);
import "DPI-C" function void dpi_fsgnjn(input bit enable, input int dst_fmt, input longint a, input longint b, output longint result);
import "DPI-C" function void dpi_fsgnjx(input bit enable, input int dst_fmt, input longint a, input longint b, output longint result);

import "DPI-C" function void dpi_flt(input bit enable, input int dst_fmt, input longint a, input longint b, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_fle(input bit enable, input int dst_fmt, input longint a, input longint b, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_feq(input bit enable, input int dst_fmt, input longint a, input longint b, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_fmin(input bit enable, input int dst_fmt, input longint a, input longint b, output longint result, output bit[4:0] fflags);
import "DPI-C" function void dpi_fmax(input bit enable, input int dst_fmt, input longint a, input longint b, output longint result, output bit[4:0] fflags);

`endif
