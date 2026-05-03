#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cmath>
#include <fstream>
#include <numeric>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include "mlx/compile.h"
#include "mlx/c/array.h"
#include "mlx/c/device.h"
#include "mlx/c/error.h"
#include "mlx/c/map.h"
#include "mlx/c/ops.h"
#include "mlx/c/stream.h"
#include "mlx/c/string.h"
#include "mlx/c/vector.h"
#include "mlx/c/version.h"
#include "mlx/fast.h"
#include "mlx/io.h"
#include "mlx/mlx.h"
#include "mlx/primitives.h"

namespace {

using mlx::core::array;
using StringToArrayMap = std::unordered_map<std::string, array>;
using StringToStringMap = std::unordered_map<std::string, std::string>;
using StringToArrayIter = StringToArrayMap::iterator;
using StringToStringIter = StringToStringMap::iterator;

enum LoweredProgramTag : uint8_t {
  LOWERED_PARAM = 1,
  LOWERED_CONSTANT = 2,
  LOWERED_STACK = 3,
  LOWERED_MONAD = 4,
  LOWERED_DYAD = 5,
  LOWERED_REDUCE_BUILTIN = 6,
  LOWERED_REDUCE_SEEDED_BUILTIN = 7,
  LOWERED_SCAN_BUILTIN = 8,
  LOWERED_SCAN_SEEDED_BUILTIN = 9,
  LOWERED_INDEX = 10,
  LOWERED_SELECT = 11,
};

constexpr uint8_t OP_EXP = 'E';
constexpr uint8_t OP_LOG = 'L';
constexpr uint8_t OP_SIN = 'I';
constexpr uint8_t OP_COS = 'O';
constexpr uint8_t OP_TANH = 'T';
constexpr uint8_t OP_SIGMOID = 'S';

struct LoweredProgramInstr {
  uint8_t tag;
  uint8_t op;
  uint16_t reserved;
  uint32_t a;
  uint32_t b;
  uint32_t c;
};

template <typename T>
T* ptr(void* ctx) {
  return static_cast<T*>(ctx);
}

template <typename T>
const T* ptr(const void* ctx) {
  return static_cast<const T*>(ctx);
}

mlx::core::Dtype to_cpp_dtype(mlx_dtype dtype) {
  switch (dtype) {
    case MLX_BOOL:
      return mlx::core::bool_;
    case MLX_UINT8:
      return mlx::core::uint8;
    case MLX_UINT16:
      return mlx::core::uint16;
    case MLX_UINT32:
      return mlx::core::uint32;
    case MLX_UINT64:
      return mlx::core::uint64;
    case MLX_INT8:
      return mlx::core::int8;
    case MLX_INT16:
      return mlx::core::int16;
    case MLX_INT32:
      return mlx::core::int32;
    case MLX_INT64:
      return mlx::core::int64;
    case MLX_FLOAT16:
      return mlx::core::float16;
    case MLX_FLOAT32:
      return mlx::core::float32;
    case MLX_FLOAT64:
      return mlx::core::float64;
    case MLX_BFLOAT16:
      return mlx::core::bfloat16;
    case MLX_COMPLEX64:
      return mlx::core::complex64;
  }
  throw std::runtime_error("unknown mlx dtype");
}

mlx_dtype to_c_dtype(mlx::core::Dtype dtype) {
  switch (dtype) {
    case mlx::core::bool_:
      return MLX_BOOL;
    case mlx::core::uint8:
      return MLX_UINT8;
    case mlx::core::uint16:
      return MLX_UINT16;
    case mlx::core::uint32:
      return MLX_UINT32;
    case mlx::core::uint64:
      return MLX_UINT64;
    case mlx::core::int8:
      return MLX_INT8;
    case mlx::core::int16:
      return MLX_INT16;
    case mlx::core::int32:
      return MLX_INT32;
    case mlx::core::int64:
      return MLX_INT64;
    case mlx::core::float16:
      return MLX_FLOAT16;
    case mlx::core::float32:
      return MLX_FLOAT32;
    case mlx::core::float64:
      return MLX_FLOAT64;
    case mlx::core::bfloat16:
      return MLX_BFLOAT16;
    case mlx::core::complex64:
      return MLX_COMPLEX64;
  }
  throw std::runtime_error("unknown cpp dtype");
}

void append_json_escaped(std::ostringstream& out, const std::string& value) {
  for (unsigned char ch : value) {
    switch (ch) {
      case '\\':
        out << "\\\\";
        break;
      case '"':
        out << "\\\"";
        break;
      case '\b':
        out << "\\b";
        break;
      case '\f':
        out << "\\f";
        break;
      case '\n':
        out << "\\n";
        break;
      case '\r':
        out << "\\r";
        break;
      case '\t':
        out << "\\t";
        break;
      default:
        if (ch < 0x20) {
          char buf[7];
          std::snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned int>(ch));
          out << buf;
        } else {
          out << static_cast<char>(ch);
        }
    }
  }
}

std::string dtype_to_safetensor_str(mlx::core::Dtype dtype) {
  switch (dtype) {
    case mlx::core::float32:
      return "F32";
    case mlx::core::float64:
      return "F64";
    case mlx::core::bfloat16:
      return "BF16";
    case mlx::core::float16:
      return "F16";
    case mlx::core::int64:
      return "I64";
    case mlx::core::int32:
      return "I32";
    case mlx::core::int16:
      return "I16";
    case mlx::core::int8:
      return "I8";
    case mlx::core::uint64:
      return "U64";
    case mlx::core::uint32:
      return "U32";
    case mlx::core::uint16:
      return "U16";
    case mlx::core::uint8:
      return "U8";
    case mlx::core::bool_:
      return "BOOL";
    case mlx::core::complex64:
      return "C64";
  }
  throw std::runtime_error("[save_safetensors] received invalid dtype.");
}

void append_json_string(std::ostringstream& out, const std::string& value) {
  out << '"';
  append_json_escaped(out, value);
  out << '"';
}

void append_shape_json(std::ostringstream& out, const mlx::core::Shape& shape) {
  out << '[';
  for (size_t i = 0; i < shape.size(); ++i) {
    if (i != 0) {
      out << ',';
    }
    out << shape[i];
  }
  out << ']';
}

void save_safetensors_with_object_metadata(
    std::string file,
    const StringToArrayMap& arrays_in,
    const StringToStringMap& metadata_in) {
  if (file.length() < 12 ||
      file.substr(file.length() - 12, 12) != ".safetensors") {
    file += ".safetensors";
  }

  auto out_stream = std::make_shared<mlx::core::io::FileWriter>(std::move(file));
  if (!out_stream->good() || !out_stream->is_open()) {
    throw std::runtime_error(
        "[save_safetensors] Failed to open " + out_stream->label());
  }

  auto arrays = arrays_in;
  {
    std::vector<array> to_eval;
    to_eval.reserve(arrays.size());
    for (auto& [_, value] : arrays) {
      value = mlx::core::contiguous(value);
      to_eval.push_back(value);
    }
    mlx::core::eval(std::move(to_eval));
  }

  std::ostringstream header;
  header << "{\"__metadata__\":";
  if (metadata_in.empty()) {
    header << "null";
  } else {
    header << '{';
    bool first_metadata = true;
    for (const auto& [key, value] : metadata_in) {
      if (!first_metadata) {
        header << ',';
      }
      append_json_string(header, key);
      header << ':';
      append_json_string(header, value);
      first_metadata = false;
    }
    header << '}';
  }

  size_t offset = 0;
  for (const auto& [key, arr] : arrays) {
    if (arr.nbytes() == 0) {
      throw std::invalid_argument(
          "[save_safetensors] cannot serialize an empty array key: " + key);
    }

    header << ',';
    append_json_string(header, key);
    header << ":{\"dtype\":";
    append_json_string(header, dtype_to_safetensor_str(arr.dtype()));
    header << ",\"shape\":";
    append_shape_json(header, arr.shape());
    header << ",\"data_offsets\":[" << offset << ',' << (offset + arr.nbytes()) << "]}";
    offset += arr.nbytes();
  }
  header << '}';

  const auto header_text = header.str();
  uint64_t header_len = header_text.length();
  out_stream->write(reinterpret_cast<char*>(&header_len), 8);
  out_stream->write(header_text.c_str(), header_len);
  for (const auto& [_, arr] : arrays) {
    out_stream->write(arr.data<char>(), arr.nbytes());
  }
}

mlx::core::Device::DeviceType to_cpp_device_type(mlx_device_type type) {
  switch (type) {
    case MLX_CPU:
      return mlx::core::Device::cpu;
    case MLX_GPU:
      return mlx::core::Device::gpu;
  }
  throw std::runtime_error("unknown device type");
}

mlx_device_type to_c_device_type(mlx::core::Device::DeviceType type) {
  switch (type) {
    case mlx::core::Device::cpu:
      return MLX_CPU;
    case mlx::core::Device::gpu:
      return MLX_GPU;
  }
  throw std::runtime_error("unknown cpp device type");
}

array& get_array(mlx_array arr) {
  return *ptr<array>(arr.ctx);
}

const array& get_array_const(mlx_array arr) {
  return *ptr<array>(arr.ctx);
}

mlx::core::Device& get_device(mlx_device dev) {
  return *ptr<mlx::core::Device>(dev.ctx);
}

const mlx::core::Device& get_device_const(mlx_device dev) {
  return *ptr<mlx::core::Device>(dev.ctx);
}

mlx::core::Stream& get_stream(mlx_stream stream) {
  return *ptr<mlx::core::Stream>(stream.ctx);
}

const mlx::core::Stream& get_stream_const(mlx_stream stream) {
  return *ptr<mlx::core::Stream>(stream.ctx);
}

mlx::core::Stream stream_or_default(mlx_stream stream) {
  if (stream.ctx) {
    return get_stream_const(stream);
  }
  return mlx::core::default_stream(mlx::core::default_device());
}

StringToArrayMap& get_string_to_array_map(mlx_map_string_to_array map) {
  return *ptr<StringToArrayMap>(map.ctx);
}

const StringToArrayMap& get_string_to_array_map_const(mlx_map_string_to_array map) {
  return *ptr<const StringToArrayMap>(map.ctx);
}

StringToStringMap& get_string_to_string_map(mlx_map_string_to_string map) {
  return *ptr<StringToStringMap>(map.ctx);
}

const StringToStringMap& get_string_to_string_map_const(mlx_map_string_to_string map) {
  return *ptr<const StringToStringMap>(map.ctx);
}

StringToArrayIter& get_string_to_array_iter(mlx_map_string_to_array_iterator it) {
  return *ptr<StringToArrayIter>(it.ctx);
}

StringToArrayMap& get_string_to_array_iter_map(mlx_map_string_to_array_iterator it) {
  return *ptr<StringToArrayMap>(it.map_ctx);
}

StringToStringIter& get_string_to_string_iter(mlx_map_string_to_string_iterator it) {
  return *ptr<StringToStringIter>(it.ctx);
}

StringToStringMap& get_string_to_string_iter_map(mlx_map_string_to_string_iterator it) {
  return *ptr<StringToStringMap>(it.map_ctx);
}

int replace_array(mlx_array* out, const array& value) {
  try {
    if (out->ctx) {
      get_array(*out) = value;
    } else {
      out->ctx = new array(value);
    }
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_set_default_device_type(mlx_device_type type, int index) {
  try {
    mlx::core::set_default_device(mlx::core::Device(to_cpp_device_type(type), index));
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

array broadcast_axis0_vector(const array& value, size_t target_ndim) {
  mlx::core::Shape dims(target_ndim, 1);
  dims[0] = value.shape(0);
  return mlx::core::reshape(value, dims);
}

array broadcast_last_axis_vector(const array& value, size_t target_ndim) {
  mlx::core::Shape dims(target_ndim, 1);
  dims[target_ndim - 1] = value.shape(0);
  return mlx::core::reshape(value, dims);
}

array sam3_linear_last_dim(const array& value, const array& weight, const array& bias, mlx::core::Stream stream) {
  const auto last_dim = value.shape(value.ndim() - 1);
  const auto rows = value.size() / last_dim;
  auto flat = mlx::core::reshape(
      value,
      mlx::core::Shape{static_cast<int>(rows), static_cast<int>(last_dim)},
      stream);
  auto out = mlx::core::matmul(flat, mlx::core::transpose(weight, stream), stream);
  out = out + broadcast_last_axis_vector(bias, out.ndim());
  auto out_shape = value.shape();
  out_shape.back() = weight.shape(0);
  return mlx::core::reshape(out, out_shape, stream);
}

array sam3_relu(const array& value, mlx::core::Stream stream) {
  return mlx::core::maximum(value, array(0.0f), stream);
}

array reverse_axis0(const array& value) {
  if (value.ndim() == 0) {
    throw std::runtime_error("reverse requires a sequence");
  }
  const auto len = value.shape(0);
  auto idx = mlx::core::arange(len - 1, -1, -1, mlx::core::int32);
  return value.ndim() <= 1 ? mlx::core::take(value, idx) : mlx::core::take(value, idx, 0);
}

int32_t lowered_count_scalar(const array& value) {
  if (value.ndim() != 0) {
    throw std::runtime_error("reshape count requires a scalar");
  }
  switch (value.dtype()) {
    case mlx::core::bool_:
      return value.item<bool>() ? 1 : 0;
    case mlx::core::int32:
      return value.item<int32_t>();
    case mlx::core::int64:
      return static_cast<int32_t>(value.item<int64_t>());
    case mlx::core::uint32:
      return static_cast<int32_t>(value.item<uint32_t>());
    default:
      throw std::runtime_error("reshape count requires an integer scalar");
  }
}

array lowered_concat(array left, array right) {
  if (left.ndim() == 0) {
    left = mlx::core::reshape(left, {1});
  }
  if (right.ndim() == 0) {
    right = mlx::core::reshape(right, {1});
  }
  if (left.ndim() != right.ndim()) {
    throw std::runtime_error("concat rank mismatch");
  }
  if (left.dtype() != right.dtype()) {
    throw std::runtime_error("concat type mismatch");
  }
  for (int axis = 1; axis < left.ndim(); ++axis) {
    if (left.shape(axis) != right.shape(axis)) {
      throw std::runtime_error("concat shape mismatch");
    }
  }
  return mlx::core::concatenate(std::vector<array>{left, right});
}

array lowered_reshape(const array& left, array right) {
  const auto count = lowered_count_scalar(left);
  if (count <= 0) {
    throw std::runtime_error("reshape count must be positive");
  }
  if (right.ndim() == 0) {
    right = mlx::core::reshape(right, {1});
  }
  if (right.ndim() != 1) {
    throw std::runtime_error("reshape requires a vector");
  }
  if (right.shape(0) % count != 0) {
    throw std::runtime_error("reshape length mismatch");
  }
  return mlx::core::reshape(right, {right.shape(0) / count, count});
}

array bool_where_indices_array(const array& mask) {
  auto contiguous = mlx::core::contiguous(mask);
  contiguous.eval();
  contiguous.wait();
  if (contiguous.dtype() != mlx::core::bool_) {
    throw std::invalid_argument("[bool_where_indices] mask must be boolean.");
  }
  std::vector<int32_t> indices;
  indices.reserve(contiguous.size());
  const bool* data = contiguous.data<bool>();
  for (int32_t i = 0; i < static_cast<int32_t>(contiguous.size()); ++i) {
    if (data[i]) {
      indices.push_back(i);
    }
  }
  const mlx::core::Shape shape = {static_cast<int>(indices.size())};
  return array(indices.data(), shape, mlx::core::int32);
}

array lowered_iota(const array& value) {
  if (value.ndim() == 0) {
    const auto count = lowered_count_scalar(value);
    if (count < 0) {
      throw std::runtime_error("iota count must be non-negative");
    }
    return mlx::core::arange(count, mlx::core::int32);
  }

  const array mask = [&]() -> array {
    switch (value.dtype()) {
      case mlx::core::bool_:
        return value;
      case mlx::core::int32:
      case mlx::core::int64:
      case mlx::core::uint32: {
        auto zeros = mlx::core::subtract(value, value);
        return mlx::core::logical_not(mlx::core::equal(value, zeros));
      }
      default:
        throw std::runtime_error("iota requires an integer-like array");
    }
  }();

  return bool_where_indices_array(mask);
}

array apply_lowered_monad(uint8_t op, const array& value) {
  switch (op) {
    case '+':
    case '*':
      return value;
    case '%':
      if (value.dtype() == mlx::core::bool_) {
        throw std::runtime_error("sqrt requires a numeric array");
      }
      return mlx::core::sqrt(
          value.dtype() == mlx::core::float32 || value.dtype() == mlx::core::float64
              ? value
              : mlx::core::astype(value, mlx::core::float32));
    case '-':
      return mlx::core::negative(value);
    case '&':
      if (value.ndim() < 2) {
        throw std::runtime_error("transpose requires rank >= 2");
      }
      return mlx::core::transpose(value);
    case '|':
      return reverse_axis0(value);
    case '#':
      return array(static_cast<int32_t>(value.ndim() == 0 ? 1 : value.shape(0)));
    case '!':
      return lowered_iota(value);
    case OP_EXP:
      return mlx::core::exp(value);
    case OP_LOG:
      return mlx::core::log(value);
    case OP_SIN:
      return mlx::core::sin(value);
    case OP_COS:
      return mlx::core::cos(value);
    case OP_TANH:
      return mlx::core::tanh(value);
    case OP_SIGMOID:
      return mlx::core::sigmoid(value);
    default:
      throw std::runtime_error("unsupported lowered monad");
  }
}

array apply_lowered_dyad(uint8_t op, array left, array right) {
  if (op == '+' || op == '-' || op == '*' || op == '%') {
    if (left.dtype() == mlx::core::bool_) {
      left = mlx::core::astype(left, mlx::core::int32);
    }
    if (right.dtype() == mlx::core::bool_) {
      right = mlx::core::astype(right, mlx::core::int32);
    }
  }

  if (left.ndim() > 1 && right.ndim() == 1 && left.shape(0) == right.shape(0)) {
    right = broadcast_axis0_vector(right, left.ndim());
  } else if (right.ndim() > 1 && left.ndim() == 1 && right.shape(0) == left.shape(0)) {
    left = broadcast_axis0_vector(left, right.ndim());
  }

  switch (op) {
    case '+':
      return mlx::core::add(left, right);
    case '-':
      return mlx::core::subtract(left, right);
    case '*':
      return mlx::core::multiply(left, right);
    case '%':
      return mlx::core::divide(left, right);
    case '&':
      return left.dtype() == mlx::core::bool_ || right.dtype() == mlx::core::bool_
                 ? mlx::core::logical_and(left, right)
                 : mlx::core::minimum(left, right);
    case '|':
      return left.dtype() == mlx::core::bool_ || right.dtype() == mlx::core::bool_
                 ? mlx::core::logical_or(left, right)
                 : mlx::core::maximum(left, right);
    case '!':
      if (left.dtype() == mlx::core::bool_ || right.dtype() == mlx::core::bool_) {
        throw std::runtime_error("mod requires numeric arrays");
      }
      return mlx::core::remainder(right, left);
    case '<':
      return mlx::core::less(left, right);
    case '>':
      return mlx::core::greater(left, right);
    case '=':
      return mlx::core::equal(left, right);
    case ',':
      return lowered_concat(left, right);
    case '^':
      return lowered_reshape(left, right);
    case '.':
      return mlx::core::matmul(left, right);
    default:
      throw std::runtime_error("unsupported lowered dyad");
  }
}

array apply_lowered_reduce(uint8_t op, const array& value) {
  if (value.ndim() == 0) {
    return value;
  }
  switch (op) {
    case '+':
      return mlx::core::sum(value, 0, false);
    case '*':
      return mlx::core::prod(value, 0, false);
    case '&':
      return mlx::core::min(value, 0, false);
    case '|':
      return mlx::core::max(value, 0, false);
    default:
      throw std::runtime_error("unsupported lowered reduce");
  }
}

array apply_lowered_seeded_reduce(uint8_t op, const array& seed, const array& value) {
  auto reduced = apply_lowered_reduce(op, value);
  switch (op) {
    case '+':
      return mlx::core::add(seed, reduced);
    case '*':
      return mlx::core::multiply(seed, reduced);
    case '&':
      return mlx::core::minimum(seed, reduced);
    case '|':
      return mlx::core::maximum(seed, reduced);
    default:
      throw std::runtime_error("unsupported lowered seeded reduce");
  }
}

array apply_lowered_scan(uint8_t op, const array& value) {
  if (value.ndim() == 0) {
    throw std::runtime_error("scan requires a sequence");
  }
  switch (op) {
    case '+':
      return mlx::core::cumsum(value, 0, false, true);
    case '*':
      return mlx::core::cumprod(value, 0, false, true);
    default:
      throw std::runtime_error("unsupported lowered scan");
  }
}

array apply_lowered_seeded_scan(uint8_t op, const array& seed, const array& value) {
  auto scanned = apply_lowered_scan(op, value);
  switch (op) {
    case '+':
      return mlx::core::add(seed, scanned);
    case '*':
      return mlx::core::multiply(seed, scanned);
    default:
      throw std::runtime_error("unsupported lowered seeded scan");
  }
}

array execute_lowered_program(
    const LoweredProgramInstr* program,
    size_t program_len,
    const uint32_t* refs,
    size_t refs_len,
    const std::vector<array>& consts,
    const std::vector<array>& inputs,
    uint32_t root) {
  std::vector<array> values;
  values.reserve(program_len);

  for (size_t idx = 0; idx < program_len; ++idx) {
    const auto& instr = program[idx];
    switch (instr.tag) {
      case LOWERED_PARAM: {
        if (instr.a >= inputs.size()) {
          throw std::runtime_error("lowered param out of bounds");
        }
        values.push_back(inputs[instr.a]);
        break;
      }
      case LOWERED_CONSTANT: {
        if (instr.a >= consts.size()) {
          throw std::runtime_error("lowered const out of bounds");
        }
        values.push_back(consts[instr.a]);
        break;
      }
      case LOWERED_STACK: {
        if (static_cast<size_t>(instr.a) + static_cast<size_t>(instr.b) > refs_len) {
          throw std::runtime_error("lowered stack refs out of bounds");
        }
        std::vector<array> items;
        items.reserve(instr.b);
        for (size_t item = 0; item < instr.b; ++item) {
          const auto ref = refs[instr.a + item];
          if (ref >= values.size()) {
            throw std::runtime_error("lowered stack value out of bounds");
          }
          items.push_back(values[ref]);
        }
        values.push_back(mlx::core::stack(items));
        break;
      }
      case LOWERED_MONAD: {
        if (instr.a >= values.size()) {
          throw std::runtime_error("lowered monad operand out of bounds");
        }
        values.push_back(apply_lowered_monad(instr.op, values[instr.a]));
        break;
      }
      case LOWERED_DYAD: {
        if (instr.a >= values.size() || instr.b >= values.size()) {
          throw std::runtime_error("lowered dyad operand out of bounds");
        }
        values.push_back(apply_lowered_dyad(instr.op, values[instr.a], values[instr.b]));
        break;
      }
      case LOWERED_REDUCE_BUILTIN: {
        if (instr.a >= values.size()) {
          throw std::runtime_error("lowered reduce operand out of bounds");
        }
        values.push_back(apply_lowered_reduce(instr.op, values[instr.a]));
        break;
      }
      case LOWERED_REDUCE_SEEDED_BUILTIN: {
        if (instr.a >= values.size() || instr.b >= values.size()) {
          throw std::runtime_error("lowered seeded reduce operand out of bounds");
        }
        values.push_back(apply_lowered_seeded_reduce(instr.op, values[instr.a], values[instr.b]));
        break;
      }
      case LOWERED_SCAN_BUILTIN: {
        if (instr.a >= values.size()) {
          throw std::runtime_error("lowered scan operand out of bounds");
        }
        values.push_back(apply_lowered_scan(instr.op, values[instr.a]));
        break;
      }
      case LOWERED_SCAN_SEEDED_BUILTIN: {
        if (instr.a >= values.size() || instr.b >= values.size()) {
          throw std::runtime_error("lowered seeded scan operand out of bounds");
        }
        values.push_back(apply_lowered_seeded_scan(instr.op, values[instr.a], values[instr.b]));
        break;
      }
      case LOWERED_INDEX: {
        if (instr.a >= values.size() || instr.b >= values.size()) {
          throw std::runtime_error("lowered index operand out of bounds");
        }
        const auto& value = values[instr.a];
        const auto& index = values[instr.b];
        if (value.ndim() == 0) {
          throw std::runtime_error("cannot index scalar");
        }
        values.push_back(
            value.ndim() <= 1 ? mlx::core::take(value, index)
                              : mlx::core::take(value, index, 0));
        break;
      }
      case LOWERED_SELECT: {
        if (instr.a >= values.size() || instr.b >= values.size() || instr.c >= values.size()) {
          throw std::runtime_error("lowered select operand out of bounds");
        }
        values.push_back(mlx::core::where(values[instr.a], values[instr.b], values[instr.c]));
        break;
      }
      default:
        throw std::runtime_error("unsupported lowered program node");
    }
  }

  if (root >= values.size()) {
    throw std::runtime_error("lowered root out of bounds");
  }
  return values[root];
}

mlx::core::Shape make_shape(const int* shape, int dim) {
  return mlx::core::Shape(shape, shape + dim);
}

template <typename T>
int item_value(T* out, mlx_array arr) {
  try {
    *out = get_array(arr).item<T>();
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

template <typename T>
const T* data_ptr(mlx_array arr) {
  try {
    auto& a = get_array(arr);
    a.eval();
    a.wait();
    return a.data<T>();
  } catch (std::exception& e) {
    mlx_error(e.what());
    return nullptr;
  }
}

template <typename Fn>
int unary_array(mlx_array* out, mlx_array a, mlx_stream s, Fn&& fn) {
  try {
    return replace_array(out, fn(get_array(a), stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

template <typename Fn>
int binary_array(mlx_array* out, mlx_array a, mlx_array b, mlx_stream s, Fn&& fn) {
  try {
    return replace_array(out, fn(get_array(a), get_array(b), stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

std::vector<array> gelu_approx_impl(const std::vector<array>& inputs) {
  const auto& x = inputs[0];
  const auto half = array(0.5f, x.dtype());
  const auto one = array(1.0f, x.dtype());
  const auto coeff = array(0.044715f, x.dtype());
  const auto sqrt_2_over_pi = array(std::sqrt(2.0f / static_cast<float>(M_PI)), x.dtype());
  const auto x3 = mlx::core::power(x, array(3.0f, x.dtype()));
  auto out = half * x * (one + mlx::core::tanh(sqrt_2_over_pi * (x + coeff * x3)));
  return {mlx::core::astype(out, x.dtype())};
}

std::vector<array> mlp_dense_impl(const std::vector<array>& inputs) {
  const auto& x = inputs[0];
  const auto& gate_w = inputs[1];
  const auto& up_w = inputs[2];
  const auto& down_w = inputs[3];
  auto gate = mlx::core::matmul(x, gate_w);
  auto up = mlx::core::matmul(x, up_w);
  const auto half = array(0.5f, gate.dtype());
  const auto one = array(1.0f, gate.dtype());
  const auto coeff = array(0.044715f, gate.dtype());
  const auto sqrt_2_over_pi = array(std::sqrt(2.0f / static_cast<float>(M_PI)), gate.dtype());
  const auto gate3 = mlx::core::power(gate, array(3.0f, gate.dtype()));
  auto geglu = half * gate * (one + mlx::core::tanh(sqrt_2_over_pi * (gate + coeff * gate3))) * up;
  return {mlx::core::astype(mlx::core::matmul(geglu, down_w), x.dtype())};
}

} // namespace

extern "C" mlx_string mlx_string_new(void) {
  return mlx_string{new std::string()};
}

extern "C" void mlx_set_error_handler(
    mlx_error_handler_func,
    void*,
    void (*)(void*)) {}

extern "C" void _mlx_error(const char* file, const int line, const char* fmt, ...) {
  std::fprintf(stderr, "mlx-c-mini error at %s:%d: ", file ? file : "<unknown>", line);
  va_list args;
  va_start(args, fmt);
  std::vfprintf(stderr, fmt, args);
  va_end(args);
  std::fprintf(stderr, "\n");
}

extern "C" mlx_string mlx_string_new_data(const char* str) {
  return mlx_string{new std::string(str ? str : "")};
}

extern "C" int mlx_string_set(mlx_string* str, const mlx_string src) {
  try {
    if (!str->ctx) {
      str->ctx = new std::string();
    }
    *ptr<std::string>(str->ctx) = *ptr<std::string>(src.ctx);
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" const char* mlx_string_data(mlx_string str) {
  return str.ctx ? ptr<std::string>(str.ctx)->c_str() : "";
}

extern "C" int mlx_string_free(mlx_string str) {
  delete ptr<std::string>(str.ctx);
  return 0;
}

extern "C" int mlx_version(mlx_string* str) {
  try {
    if (!str->ctx) {
      str->ctx = new std::string();
    }
    *ptr<std::string>(str->ctx) = mlx::core::version();
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" mlx_array mlx_array_new(void) {
  return mlx_array{nullptr};
}

extern "C" int mlx_array_free(mlx_array arr) {
  delete ptr<array>(arr.ctx);
  return 0;
}

extern "C" int mlx_array_set(mlx_array* arr, const mlx_array src) {
  return replace_array(arr, get_array_const(src));
}

extern "C" mlx_array mlx_array_new_bool(bool val) {
  return mlx_array{new array(val)};
}

extern "C" mlx_array mlx_array_new_int(int val) {
  return mlx_array{new array(val)};
}

extern "C" mlx_array mlx_array_new_float32(float val) {
  return mlx_array{new array(val, mlx::core::float32)};
}

extern "C" mlx_array mlx_array_new_float(float val) {
  return mlx_array_new_float32(val);
}

extern "C" mlx_array mlx_array_new_float64(double val) {
  return mlx_array{new array(val, mlx::core::float64)};
}

extern "C" mlx_array mlx_array_new_double(double val) {
  return mlx_array_new_float64(val);
}

extern "C" int mlx_array_set_bool(mlx_array* arr, bool val) {
  return replace_array(arr, array(val));
}

extern "C" int mlx_array_set_int(mlx_array* arr, int val) {
  return replace_array(arr, array(val));
}

extern "C" int mlx_array_set_float32(mlx_array* arr, float val) {
  return replace_array(arr, array(val, mlx::core::float32));
}

extern "C" int mlx_array_set_float(mlx_array* arr, float val) {
  return mlx_array_set_float32(arr, val);
}

extern "C" int mlx_array_set_float64(mlx_array* arr, double val) {
  return replace_array(arr, array(val, mlx::core::float64));
}

extern "C" int mlx_array_set_double(mlx_array* arr, double val) {
  return mlx_array_set_float64(arr, val);
}

extern "C" int mlx_array_set_data(
    mlx_array* arr,
    const void* data,
    const int* shape,
    int dim,
    mlx_dtype dtype) {
  try {
    const auto cpp_shape = make_shape(shape, dim);
    const auto cpp_dtype = to_cpp_dtype(dtype);
    switch (dtype) {
      case MLX_BOOL:
        return replace_array(arr, array((const bool*)data, cpp_shape, cpp_dtype));
      case MLX_UINT8:
        return replace_array(arr, array((const uint8_t*)data, cpp_shape, cpp_dtype));
      case MLX_UINT16:
        return replace_array(arr, array((const uint16_t*)data, cpp_shape, cpp_dtype));
      case MLX_UINT32:
        return replace_array(arr, array((const uint32_t*)data, cpp_shape, cpp_dtype));
      case MLX_UINT64:
        return replace_array(arr, array((const uint64_t*)data, cpp_shape, cpp_dtype));
      case MLX_INT8:
        return replace_array(arr, array((const int8_t*)data, cpp_shape, cpp_dtype));
      case MLX_INT16:
        return replace_array(arr, array((const int16_t*)data, cpp_shape, cpp_dtype));
      case MLX_INT32:
        return replace_array(arr, array((const int32_t*)data, cpp_shape, cpp_dtype));
      case MLX_INT64:
        return replace_array(arr, array((const int64_t*)data, cpp_shape, cpp_dtype));
      case MLX_FLOAT32:
        return replace_array(arr, array((const float*)data, cpp_shape, cpp_dtype));
      case MLX_FLOAT64:
        return replace_array(arr, array((const double*)data, cpp_shape, cpp_dtype));
      default:
        mlx_error("unsupported dtype in mlx_array_set_data");
        return 1;
    }
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" mlx_array mlx_array_new_data(
    const void* data,
    const int* shape,
    int dim,
    mlx_dtype dtype) {
  mlx_array out = mlx_array_new();
  if (mlx_array_set_data(&out, data, shape, dim, dtype)) {
    return mlx_array_new();
  }
  return out;
}

extern "C" size_t mlx_array_itemsize(const mlx_array arr) {
  return get_array_const(arr).itemsize();
}

extern "C" size_t mlx_array_size(const mlx_array arr) {
  return get_array_const(arr).size();
}

extern "C" size_t mlx_array_nbytes(const mlx_array arr) {
  return get_array_const(arr).nbytes();
}

extern "C" size_t mlx_array_ndim(const mlx_array arr) {
  return get_array_const(arr).ndim();
}

extern "C" const int* mlx_array_shape(const mlx_array arr) {
  return (const int*)get_array_const(arr).shape().data();
}

extern "C" int mlx_array_dim(const mlx_array arr, int dim) {
  return get_array_const(arr).shape(dim);
}

extern "C" mlx_dtype mlx_array_dtype(const mlx_array arr) {
  return to_c_dtype(get_array_const(arr).dtype());
}

extern "C" int mlx_array_eval(mlx_array arr) {
  try {
    get_array(arr).eval();
    get_array(arr).wait();
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_array_tostring(mlx_string* str, const mlx_array arr) {
  try {
    if (!str->ctx) {
      str->ctx = new std::string();
    }
    std::ostringstream os;
    os << get_array_const(arr);
    *ptr<std::string>(str->ctx) = os.str();
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_array_item_bool(bool* res, const mlx_array arr) {
  return item_value(res, arr);
}

extern "C" int mlx_array_item_uint32(uint32_t* res, const mlx_array arr) {
  return item_value(res, arr);
}

extern "C" int mlx_array_item_int32(int32_t* res, const mlx_array arr) {
  return item_value(res, arr);
}

extern "C" int mlx_array_item_int64(int64_t* res, const mlx_array arr) {
  return item_value(res, arr);
}

extern "C" int mlx_array_item_float32(float* res, const mlx_array arr) {
  return item_value(res, arr);
}

extern "C" int mlx_array_item_float64(double* res, const mlx_array arr) {
  return item_value(res, arr);
}

extern "C" const bool* mlx_array_data_bool(const mlx_array arr) {
  return data_ptr<bool>(arr);
}

extern "C" const uint32_t* mlx_array_data_uint32(const mlx_array arr) {
  return data_ptr<uint32_t>(arr);
}

extern "C" const int32_t* mlx_array_data_int32(const mlx_array arr) {
  return data_ptr<int32_t>(arr);
}

extern "C" const int64_t* mlx_array_data_int64(const mlx_array arr) {
  return data_ptr<int64_t>(arr);
}

extern "C" const float* mlx_array_data_float32(const mlx_array arr) {
  return data_ptr<float>(arr);
}

extern "C" const double* mlx_array_data_float64(const mlx_array arr) {
  return data_ptr<double>(arr);
}

extern "C" mlx_device mlx_device_new(void) {
  return mlx_device{nullptr};
}

extern "C" mlx_device mlx_device_new_type(mlx_device_type type, int index) {
  try {
    return mlx_device{new mlx::core::Device(to_cpp_device_type(type), index)};
  } catch (std::exception& e) {
    mlx_error(e.what());
    return mlx_device{nullptr};
  }
}

extern "C" int mlx_get_default_device(mlx_device* dev) {
  try {
    if (!dev->ctx) {
      dev->ctx = new mlx::core::Device(mlx::core::default_device());
    } else {
      get_device(*dev) = mlx::core::default_device();
    }
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_device_get_type(mlx_device_type* type, mlx_device dev) {
  try {
    *type = to_c_device_type(get_device_const(dev).type);
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_device_is_available(bool* avail, mlx_device dev) {
  try {
    *avail = mlx::core::is_available(get_device_const(dev));
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_device_free(mlx_device dev) {
  delete ptr<mlx::core::Device>(dev.ctx);
  return 0;
}

extern "C" mlx_stream mlx_stream_new(void) {
  return mlx_stream{nullptr};
}

extern "C" mlx_stream mlx_stream_new_device(mlx_device dev) {
  try {
    return mlx_stream{new mlx::core::Stream(mlx::core::default_stream(get_device_const(dev)))};
  } catch (std::exception& e) {
    mlx_error(e.what());
    return mlx_stream{nullptr};
  }
}

extern "C" int mlx_stream_free(mlx_stream stream) {
  delete ptr<mlx::core::Stream>(stream.ctx);
  return 0;
}

extern "C" mlx_vector_array mlx_vector_array_new(void) {
  return mlx_vector_array{new std::vector<array>()};
}

extern "C" int mlx_vector_array_free(mlx_vector_array vec) {
  delete ptr<std::vector<array>>(vec.ctx);
  return 0;
}

extern "C" int mlx_vector_array_append_value(mlx_vector_array vec, const mlx_array val) {
  try {
    ptr<std::vector<array>>(vec.ctx)->push_back(get_array_const(val));
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" mlx_map_string_to_array mlx_map_string_to_array_new(void) {
  return mlx_map_string_to_array{new StringToArrayMap()};
}

extern "C" int mlx_map_string_to_array_set(
    mlx_map_string_to_array* map,
    const mlx_map_string_to_array src) {
  try {
    if (!map->ctx) {
      map->ctx = new StringToArrayMap();
    }
    get_string_to_array_map(*map) = get_string_to_array_map_const(src);
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_map_string_to_array_free(mlx_map_string_to_array map) {
  delete ptr<StringToArrayMap>(map.ctx);
  return 0;
}

extern "C" int mlx_map_string_to_array_insert(
    mlx_map_string_to_array map,
    const char* key,
    const mlx_array value) {
  try {
    get_string_to_array_map(map).insert_or_assign(
        std::string(key ? key : ""),
        get_array_const(value));
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_map_string_to_array_get(
    mlx_array* value,
    const mlx_map_string_to_array map,
    const char* key) {
  try {
    const auto& cpp_map = get_string_to_array_map_const(map);
    auto it = cpp_map.find(key ? key : "");
    if (it == cpp_map.end()) {
      return 2;
    }
    return replace_array(value, it->second);
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" mlx_map_string_to_array_iterator mlx_map_string_to_array_iterator_new(
    mlx_map_string_to_array map) {
  try {
    return mlx_map_string_to_array_iterator{
        new StringToArrayIter(get_string_to_array_map(map).begin()),
        map.ctx};
  } catch (std::exception& e) {
    mlx_error(e.what());
    return mlx_map_string_to_array_iterator{nullptr, nullptr};
  }
}

extern "C" int mlx_map_string_to_array_iterator_free(
    mlx_map_string_to_array_iterator it) {
  delete ptr<StringToArrayIter>(it.ctx);
  return 0;
}

extern "C" int mlx_map_string_to_array_iterator_next(
    const char** key,
    mlx_array* value,
    mlx_map_string_to_array_iterator it) {
  try {
    auto& iter = get_string_to_array_iter(it);
    auto& map = get_string_to_array_iter_map(it);
    if (iter == map.end()) {
      return 2;
    }
    *key = iter->first.c_str();
    const int status = replace_array(value, iter->second);
    ++iter;
    return status;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" mlx_map_string_to_string mlx_map_string_to_string_new(void) {
  return mlx_map_string_to_string{new StringToStringMap()};
}

extern "C" int mlx_map_string_to_string_set(
    mlx_map_string_to_string* map,
    const mlx_map_string_to_string src) {
  try {
    if (!map->ctx) {
      map->ctx = new StringToStringMap();
    }
    get_string_to_string_map(*map) = get_string_to_string_map_const(src);
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_map_string_to_string_free(mlx_map_string_to_string map) {
  delete ptr<StringToStringMap>(map.ctx);
  return 0;
}

extern "C" int mlx_map_string_to_string_insert(
    mlx_map_string_to_string map,
    const char* key,
    const char* value) {
  try {
    get_string_to_string_map(map).insert_or_assign(
        std::string(key ? key : ""),
        std::string(value ? value : ""));
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_map_string_to_string_get(
    const char** value,
    const mlx_map_string_to_string map,
    const char* key) {
  try {
    const auto& cpp_map = get_string_to_string_map_const(map);
    auto it = cpp_map.find(key ? key : "");
    if (it == cpp_map.end()) {
      return 2;
    }
    *value = it->second.c_str();
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" mlx_map_string_to_string_iterator mlx_map_string_to_string_iterator_new(
    mlx_map_string_to_string map) {
  try {
    return mlx_map_string_to_string_iterator{
        new StringToStringIter(get_string_to_string_map(map).begin()),
        map.ctx};
  } catch (std::exception& e) {
    mlx_error(e.what());
    return mlx_map_string_to_string_iterator{nullptr, nullptr};
  }
}

extern "C" int mlx_map_string_to_string_iterator_free(
    mlx_map_string_to_string_iterator it) {
  delete ptr<StringToStringIter>(it.ctx);
  return 0;
}

extern "C" int mlx_map_string_to_string_iterator_next(
    const char** key,
    const char** value,
    mlx_map_string_to_string_iterator it) {
  try {
    auto& iter = get_string_to_string_iter(it);
    auto& map = get_string_to_string_iter_map(it);
    if (iter == map.end()) {
      return 2;
    }
    *key = iter->first.c_str();
    *value = iter->second.c_str();
    ++iter;
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_load_safetensors(
    mlx_map_string_to_array* res_0,
    mlx_map_string_to_string* res_1,
    const char* file,
    const mlx_stream s) {
  try {
    auto [arrays, metadata] = mlx::core::load_safetensors(
        std::string(file ? file : ""),
        stream_or_default(s));
    if (!res_0->ctx) {
      res_0->ctx = new StringToArrayMap();
    }
    if (!res_1->ctx) {
      res_1->ctx = new StringToStringMap();
    }
    get_string_to_array_map(*res_0) = std::move(arrays);
    get_string_to_string_map(*res_1) = std::move(metadata);
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_load_safetensor_tensor(
    mlx_array* res,
    const char* file,
    const int* shape,
    int dim,
    mlx_dtype dtype,
    uint64_t data_offset,
    const mlx_stream s) {
  (void)s;
  try {
    const auto path = std::string(file ? file : "");
    std::ifstream in(path, std::ios::binary);
    if (!in.is_open()) {
      throw std::runtime_error("[load_safetensors] Failed to open " + path);
    }

    const auto cpp_shape = make_shape(shape, dim);
    const auto cpp_dtype = to_cpp_dtype(dtype);
    const size_t nbytes =
        std::accumulate(cpp_shape.begin(), cpp_shape.end(), static_cast<size_t>(1),
                        [&](size_t acc, auto extent) { return acc * static_cast<size_t>(extent); }) *
        mlx::core::size_of(cpp_dtype);
    auto buffer = mlx::core::allocator::malloc(nbytes);
    if (nbytes != 0) {
      in.seekg(static_cast<std::streamoff>(data_offset), std::ios::beg);
      if (!in.good()) {
        throw std::runtime_error("[load_safetensors] Failed to seek " + path);
      }
      in.read(static_cast<char*>(buffer.raw_ptr()), static_cast<std::streamsize>(nbytes));
      if (in.gcount() != static_cast<std::streamsize>(nbytes)) {
        throw std::runtime_error("[load_safetensors] Failed to read tensor bytes " + path);
      }
    }
    auto value = array(buffer, cpp_shape, cpp_dtype);
    return replace_array(res, value);
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_save_safetensors(
    const char* file,
    const mlx_map_string_to_array param,
    const mlx_map_string_to_string metadata) {
  try {
    save_safetensors_with_object_metadata(
        std::string(file ? file : ""),
        get_string_to_array_map_const(param),
        get_string_to_string_map_const(metadata));
    return 0;
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_add(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::add(x, y, stream); });
}

extern "C" int mlx_subtract(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::subtract(x, y, stream); });
}

extern "C" int mlx_multiply(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::multiply(x, y, stream); });
}

extern "C" int mlx_divide(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::divide(x, y, stream); });
}

extern "C" int mlxc_power(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::power(x, y, stream); });
}

extern "C" int mlx_remainder(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::remainder(x, y, stream); });
}

extern "C" int mlx_minimum(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::minimum(x, y, stream); });
}

extern "C" int mlx_maximum(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::maximum(x, y, stream); });
}

extern "C" int mlx_less(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::less(x, y, stream); });
}

extern "C" int mlx_greater(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::greater(x, y, stream); });
}

extern "C" int mlx_equal(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::equal(x, y, stream); });
}

extern "C" int mlx_negative(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::negative(x, stream); });
}

extern "C" int mlx_logical_not(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::logical_not(x, stream); });
}

extern "C" int mlxc_logical_and(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::logical_and(x, y, stream); });
}

extern "C" int mlxc_logical_or(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::logical_or(x, y, stream); });
}

extern "C" int mlxc_sum_axis0(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) {
    if (x.ndim() == 0) return x;
    return mlx::core::sum(x, 0, false, stream);
  });
}

extern "C" int mlxc_prod_axis0(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) {
    if (x.ndim() == 0) return x;
    return mlx::core::prod(x, 0, false, stream);
  });
}

extern "C" int mlxc_min_axis0(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) {
    if (x.ndim() == 0) return x;
    return mlx::core::min(x, 0, false, stream);
  });
}

extern "C" int mlxc_max_axis0(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) {
    if (x.ndim() == 0) return x;
    return mlx::core::max(x, 0, false, stream);
  });
}

extern "C" int mlxc_cumprod0_inclusive(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::cumprod(x, 0, false, true, stream); });
}

extern "C" int mlxc_cummin0_inclusive(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::cummin(x, 0, false, true, stream); });
}

extern "C" int mlxc_cummax0_inclusive(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::cummax(x, 0, false, true, stream); });
}

extern "C" int mlx_sqrt(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::sqrt(x, stream); });
}

extern "C" int mlx_floor(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::floor(x, stream); });
}

extern "C" int mlx_astype(mlx_array* res, const mlx_array a, mlx_dtype dtype, const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::astype(get_array(a), to_cpp_dtype(dtype), stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_arange(
    mlx_array* res,
    double start,
    double stop,
    double step,
    mlx_dtype dtype,
    const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::arange(start, stop, step, to_cpp_dtype(dtype), stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_transpose(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::transpose(x, stream); });
}

extern "C" int mlx_swapaxes(mlx_array* res, const mlx_array a, int axis1, int axis2, const mlx_stream s) {
  return unary_array(res, a, s, [axis1, axis2](const array& x, auto stream) {
    return mlx::core::swapaxes(x, axis1, axis2, stream);
  });
}

extern "C" int mlx_matmul(mlx_array* res, const mlx_array a, const mlx_array b, const mlx_stream s) {
  return binary_array(res, a, b, s, [](const array& x, const array& y, auto stream) { return mlx::core::matmul(x, y, stream); });
}

extern "C" int mlx_sum(mlx_array* res, const mlx_array a, bool keepdims, const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::sum(get_array(a), keepdims, stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_cumsum(
    mlx_array* res,
    const mlx_array a,
    int axis,
    bool reverse,
    bool inclusive,
    const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::cumsum(get_array(a), axis, reverse, inclusive, stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_copy(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::copy(x, stream); });
}

extern "C" int mlx_contiguous(mlx_array* res, const mlx_array a, bool allow_col_major, const mlx_stream s) {
  return unary_array(res, a, s, [allow_col_major](const array& x, auto stream) {
    return mlx::core::contiguous(x, allow_col_major, stream);
  });
}

extern "C" int mlx_argsort(mlx_array* res, const mlx_array a, const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::argsort(get_array(a), stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_argmax(mlx_array* res, const mlx_array a, bool keepdims, const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::argmax(get_array(a), keepdims, stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_softmax_last_axis(mlx_array* res, const mlx_array a, bool precise, const mlx_stream s) {
  try {
    return replace_array(
        res,
        mlx::core::softmax(get_array(a), std::vector<int>{-1}, precise, stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_layer_norm(
    mlx_array* res,
    const mlx_array a,
    const mlx_array weight,
    const mlx_array bias,
    float eps,
    const mlx_stream s) {
  try {
    return replace_array(
        res,
        mlx::core::fast::layer_norm(
            get_array(a),
            get_array(weight),
            get_array(bias),
            eps,
            stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_conv2d(
    mlx_array* res,
    const mlx_array input,
    const mlx_array weight,
    int stride_h,
    int stride_w,
    int padding_h,
    int padding_w,
    const mlx_stream s) {
  try {
    return replace_array(
        res,
        mlx::core::conv2d(
            get_array(input),
            get_array(weight),
            {stride_h, stride_w},
            {padding_h, padding_w},
            {1, 1},
            1,
            stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_conv2d_bias(
    mlx_array* res,
    const mlx_array input,
    const mlx_array weight,
    const mlx_array bias,
    int stride_h,
    int stride_w,
    int padding_h,
    int padding_w,
    const mlx_stream s) {
  try {
    auto out = mlx::core::conv2d(
        get_array(input),
        get_array(weight),
        {stride_h, stride_w},
        {padding_h, padding_w},
        {1, 1},
        1,
        stream_or_default(s));
    out = out + broadcast_last_axis_vector(get_array(bias), out.ndim());
    return replace_array(res, out);
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_conv_transpose2d(
    mlx_array* res,
    const mlx_array input,
    const mlx_array weight,
    int stride_h,
    int stride_w,
    int padding_h,
    int padding_w,
    const mlx_stream s) {
  try {
    return replace_array(
        res,
        mlx::core::conv_transpose2d(
            get_array(input),
            get_array(weight),
            {stride_h, stride_w},
            {padding_h, padding_w},
            {1, 1},
            {0, 0},
            1,
            stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_conv_transpose2d_bias(
    mlx_array* res,
    const mlx_array input,
    const mlx_array weight,
    const mlx_array bias,
    int stride_h,
    int stride_w,
    int padding_h,
    int padding_w,
    const mlx_stream s) {
  try {
    auto out = mlx::core::conv_transpose2d(
        get_array(input),
        get_array(weight),
        {stride_h, stride_w},
        {padding_h, padding_w},
        {1, 1},
        {0, 0},
        1,
        stream_or_default(s));
    out = out + broadcast_last_axis_vector(get_array(bias), out.ndim());
    return replace_array(res, out);
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_upsample_nearest2d(
    mlx_array* res,
    const mlx_array input,
    int scale_h,
    int scale_w,
    const mlx_stream s) {
  try {
    auto out = mlx::core::repeat(get_array(input), scale_h, 1, stream_or_default(s));
    out = mlx::core::repeat(out, scale_w, 2, stream_or_default(s));
    return replace_array(res, out);
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_group_norm(
    mlx_array* res,
    const mlx_array input,
    int groups,
    const mlx_array weight,
    const mlx_array bias,
    float eps,
    const mlx_stream s) {
  try {
    const auto& x = get_array(input);
    if (x.ndim() != 4) {
      throw std::runtime_error("groupnorm expects rank-4 NHWC input");
    }
    const int batch = x.shape(0);
    const int height = x.shape(1);
    const int width = x.shape(2);
    const int channels = x.shape(3);
    if (groups <= 0 || channels % groups != 0) {
      throw std::runtime_error("groupnorm expects channels divisible by groups");
    }
    // Match MLX nn.GroupNorm's default grouping order, which reshapes NHWC to
    // [batch, -1, groups] before reducing across the middle axis.
    const int grouped_extent = (height * width * channels) / groups;
    auto grouped = mlx::core::reshape(x, {batch, grouped_extent, groups}, stream_or_default(s));
    auto mean = mlx::core::mean(grouped, 1, true, stream_or_default(s));
    auto var = mlx::core::var(grouped, 1, true, 0, stream_or_default(s));
    auto normalized = (grouped - mean) / mlx::core::sqrt(var + eps, stream_or_default(s));
    auto out = mlx::core::reshape(normalized, {batch, height, width, channels}, stream_or_default(s));
    out = out * broadcast_last_axis_vector(get_array(weight), out.ndim()) +
        broadcast_last_axis_vector(get_array(bias), out.ndim());
    return replace_array(res, out);
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_sdpa_none(
    mlx_array* res,
    const mlx_array q,
    const mlx_array k,
    const mlx_array v,
    float scale,
    const mlx_stream s) {
  try {
    return replace_array(
        res,
        mlx::core::fast::scaled_dot_product_attention(
            get_array(q),
            get_array(k),
            get_array(v),
            scale,
            "",
            std::nullopt,
            std::nullopt,
            stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_sdpa_causal(
    mlx_array* res,
    const mlx_array q,
    const mlx_array k,
    const mlx_array v,
    float scale,
    const mlx_stream s) {
  try {
    return replace_array(
        res,
        mlx::core::fast::scaled_dot_product_attention(
            get_array(q),
            get_array(k),
            get_array(v),
            scale,
            "causal",
            std::nullopt,
            std::nullopt,
            stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_sdpa_masked(
    mlx_array* res,
    const mlx_array q,
    const mlx_array k,
    const mlx_array v,
    const mlx_array mask,
    float scale,
    const mlx_stream s) {
  try {
    return replace_array(
        res,
        mlx::core::fast::scaled_dot_product_attention(
            get_array(q),
            get_array(k),
            get_array(v),
            scale,
            "array",
            get_array(mask),
            std::nullopt,
            stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_sam3_box_rpb_log(
    mlx_array* res,
    const mlx_array reference_boxes,
    const mlx_array xw0,
    const mlx_array xb0,
    const mlx_array xw1,
    const mlx_array xb1,
    const mlx_array yw0,
    const mlx_array yb0,
    const mlx_array yw1,
    const mlx_array yb1,
    int height,
    int width,
    const mlx_stream s) {
  try {
    if (height <= 0 || width <= 0) {
      throw std::runtime_error("sam3_box_rpb_log expects positive spatial dims");
    }
    const auto& boxes = get_array(reference_boxes);
    if (boxes.ndim() != 2 || boxes.shape(1) != 4) {
      throw std::runtime_error("sam3_box_rpb_log expects reference_boxes shaped (queries,4)");
    }

    const auto stream = stream_or_default(s);
    const auto queries = boxes.shape(0);
    const auto ln8 = std::log(8.0f);
    const auto eps = array(1.0e-9f);

    auto cx = mlx::core::slice(boxes, {0, 0}, {queries, 1}, {1, 1}, stream);
    auto cy = mlx::core::slice(boxes, {0, 1}, {queries, 2}, {1, 1}, stream);
    auto bw = mlx::core::slice(boxes, {0, 2}, {queries, 3}, {1, 1}, stream);
    auto bh = mlx::core::slice(boxes, {0, 3}, {queries, 4}, {1, 1}, stream);

    auto x0 = cx - bw * 0.5f;
    auto y0 = cy - bh * 0.5f;
    auto x1 = cx + bw * 0.5f;
    auto y1 = cy + bh * 0.5f;

    auto coords_w = mlx::core::arange(0.0, static_cast<double>(width), 1.0, mlx::core::float32, stream) / static_cast<float>(width);
    auto coords_h = mlx::core::arange(0.0, static_cast<double>(height), 1.0, mlx::core::float32, stream) / static_cast<float>(height);

    auto deltas_x = mlx::core::concatenate(
        std::vector<array>{
            mlx::core::reshape(coords_w, {1, width, 1}, stream) - mlx::core::reshape(x0, {queries, 1, 1}, stream),
            mlx::core::reshape(coords_w, {1, width, 1}, stream) - mlx::core::reshape(x1, {queries, 1, 1}, stream),
        },
        2,
        stream);
    auto deltas_y = mlx::core::concatenate(
        std::vector<array>{
            mlx::core::reshape(coords_h, {1, height, 1}, stream) - mlx::core::reshape(y0, {queries, 1, 1}, stream),
            mlx::core::reshape(coords_h, {1, height, 1}, stream) - mlx::core::reshape(y1, {queries, 1, 1}, stream),
        },
        2,
        stream);

    auto normalize_deltas = [&](const array& deltas) {
      auto scaled = deltas * 8.0f;
      auto abs_scaled = mlx::core::abs(scaled, stream);
      auto sign_scaled = scaled / mlx::core::maximum(abs_scaled, eps, stream);
      return sign_scaled * (mlx::core::log(abs_scaled + 1.0f, stream) / ln8);
    };

    auto x_hidden = sam3_relu(sam3_linear_last_dim(normalize_deltas(deltas_x), get_array(xw0), get_array(xb0), stream), stream);
    auto y_hidden = sam3_relu(sam3_linear_last_dim(normalize_deltas(deltas_y), get_array(yw0), get_array(yb0), stream), stream);
    auto x_proj = sam3_linear_last_dim(x_hidden, get_array(xw1), get_array(xb1), stream);
    auto y_proj = sam3_linear_last_dim(y_hidden, get_array(yw1), get_array(yb1), stream);

    auto bias = mlx::core::reshape(y_proj, {queries, height, 1, y_proj.shape(2)}, stream) +
        mlx::core::reshape(x_proj, {queries, 1, width, x_proj.shape(2)}, stream);
    bias = mlx::core::reshape(bias, {queries, height * width, bias.shape(3)}, stream);
    bias = mlx::core::transpose(bias, {2, 0, 1}, stream);
    bias = mlx::core::reshape(bias, {1, bias.shape(0), bias.shape(1), bias.shape(2)}, stream);
    auto presence_mask = mlx::core::zeros(
        mlx::core::Shape{1, static_cast<int>(bias.shape(1)), 1, static_cast<int>(bias.shape(3))},
        bias.dtype(),
        stream);
    bias = mlx::core::concatenate(std::vector<array>{presence_mask, bias}, 2, stream);
    return replace_array(res, bias);
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_rope(
    mlx_array* res,
    const mlx_array a,
    int dims,
    float base,
    int offset,
    const mlx_stream s) {
  try {
    return replace_array(
        res,
        mlx::core::fast::rope(get_array(a), dims, false, base, 1.0f, offset, std::nullopt, stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_rope_freqs(
    mlx_array* res,
    const mlx_array a,
    int dims,
    const mlx_array freqs,
    int offset,
    const mlx_stream s) {
  try {
    return replace_array(
        res,
        mlx::core::fast::rope(
            get_array(a),
            dims,
            false,
            std::nullopt,
            1.0f,
            offset,
            get_array(freqs),
            stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_exp(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::exp(x, stream); });
}

extern "C" int mlxc_gelu(mlx_array* res, const mlx_array a, const mlx_stream s) {
  try {
    const auto& x = get_array(a);
    const float inv_sqrt2 = 0.7071067811865475f;
    return replace_array(res, 0.5f * x * (1.0f + mlx::core::erf(x * inv_sqrt2, stream_or_default(s))));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_log(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::log(x, stream); });
}

extern "C" int mlxc_sin(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::sin(x, stream); });
}

extern "C" int mlxc_cos(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::cos(x, stream); });
}

extern "C" int mlxc_tanh(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::tanh(x, stream); });
}

extern "C" int mlxc_sigmoid(mlx_array* res, const mlx_array a, const mlx_stream s) {
  return unary_array(res, a, s, [](const array& x, auto stream) { return mlx::core::sigmoid(x, stream); });
}

extern "C" int mlxc_gelu_approx(mlx_array* res, const mlx_array a, const mlx_stream s) {
  try {
#if defined(__linux__)
    auto outputs = gelu_approx_impl({get_array(a)});
#else
    static auto compiled = mlx::core::compile(gelu_approx_impl, true);
    auto outputs = compiled({get_array(a)});
#endif
    return replace_array(res, outputs[0]);
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_mlp_dense(
    mlx_array* res,
    const mlx_array x,
    const mlx_array gate_w,
    const mlx_array up_w,
    const mlx_array down_w,
    const mlx_stream s) {
  try {
#if defined(__linux__)
    auto outputs = mlp_dense_impl({get_array(x), get_array(gate_w), get_array(up_w), get_array(down_w)});
#else
    static auto compiled = mlx::core::compile(mlp_dense_impl, true);
    auto outputs = compiled({get_array(x), get_array(gate_w), get_array(up_w), get_array(down_w)});
#endif
    return replace_array(res, outputs[0]);
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_rms_norm(
    mlx_array* res,
    const mlx_array x,
    const mlx_array* weight,
    float eps,
    const mlx_stream s) {
  try {
    std::optional<array> w = std::nullopt;
    if (weight != nullptr and weight->ctx != nullptr) {
      w = get_array_const(*weight);
    }
    return replace_array(
        res,
        mlx::core::fast::rms_norm(
            get_array_const(x),
            w,
            eps,
            stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_where(
    mlx_array* res,
    const mlx_array cond,
    const mlx_array left,
    const mlx_array right,
    const mlx_stream s) {
  try {
    return replace_array(
        res,
        mlx::core::where(get_array(cond), get_array(left), get_array(right), stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_bool_where_indices(
    mlx_array* res,
    const mlx_array mask,
    const mlx_stream s) {
  try {
    auto contiguous = mlx::core::contiguous(get_array(mask), false, stream_or_default(s));
    contiguous.eval();
    contiguous.wait();
    if (contiguous.dtype() != mlx::core::bool_) {
      throw std::invalid_argument("[bool_where_indices] mask must be boolean.");
    }
    if (contiguous.ndim() != 1) {
      throw std::invalid_argument("[bool_where_indices] mask must be rank 1.");
    }
    return replace_array(res, bool_where_indices_array(contiguous));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_reshape(
    mlx_array* res,
    const mlx_array a,
    const int* shape,
    size_t shape_num,
    const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::reshape(get_array(a), mlx::core::Shape(shape, shape + shape_num), stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_slice(
    mlx_array* res,
    const mlx_array a,
    const int* start,
    size_t start_num,
    const int* stop,
    size_t stop_num,
    const int* strides,
    size_t strides_num,
    const mlx_stream s) {
  try {
    return replace_array(
        res,
        mlx::core::slice(
            get_array(a),
            mlx::core::Shape(start, start + start_num),
            mlx::core::Shape(stop, stop + stop_num),
            mlx::core::Shape(strides, strides + strides_num),
            stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_slice_update(
    mlx_array* res,
    const mlx_array a,
    const mlx_array update,
    const int* start,
    size_t start_num,
    const int* stop,
    size_t stop_num,
    const int* strides,
    size_t strides_num,
    const mlx_stream s) {
  try {
    return replace_array(
        res,
        mlx::core::slice_update(
            get_array(a),
            get_array(update),
            mlx::core::Shape(start, start + start_num),
            mlx::core::Shape(stop, stop + stop_num),
            mlx::core::Shape(strides, strides + strides_num),
            stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_take(mlx_array* res, const mlx_array a, const mlx_array indices, const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::take(get_array(a), get_array(indices), stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_take_axis(
    mlx_array* res,
    const mlx_array a,
    const mlx_array indices,
    int axis,
    const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::take(get_array(a), get_array(indices), axis, stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_zeros(
    mlx_array* res,
    const int* shape,
    size_t shape_num,
    mlx_dtype dtype,
    const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::zeros(mlx::core::Shape(shape, shape + shape_num), to_cpp_dtype(dtype), stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_concatenate(mlx_array* res, const mlx_vector_array arrays, const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::concatenate(*ptr<std::vector<array>>(arrays.ctx), stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_concatenate_axis(mlx_array* res, const mlx_vector_array arrays, int axis, const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::concatenate(*ptr<std::vector<array>>(arrays.ctx), axis, stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlx_stack(mlx_array* res, const mlx_vector_array arrays, const mlx_stream s) {
  try {
    return replace_array(res, mlx::core::stack(*ptr<std::vector<array>>(arrays.ctx), stream_or_default(s)));
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_hot_value_and_grad(
    mlx_array* value_res,
    mlx_array* grad_res,
    const mlx_array input,
    int kind) {
  try {
    std::function<array(const array&)> fun;
    switch (kind) {
      case 1:
        fun = [](const array& x) { return mlx::core::multiply(x, x); };
        break;
      case 2:
        fun = [](const array& x) {
          auto xx = mlx::core::multiply(x, x);
          return mlx::core::multiply(xx, x);
        };
        break;
      case 3:
        fun = [](const array& x) {
          auto xx = mlx::core::multiply(x, x);
          return mlx::core::sum(xx, false);
        };
        break;
      default:
        mlx_error("unknown hot grad kind");
        return 1;
    }
    auto vg = mlx::core::value_and_grad(fun);
    auto result = vg(get_array(input));
    if (value_res) {
      if (replace_array(value_res, result.first) != 0) {
        return 1;
      }
    }
    return replace_array(grad_res, result.second);
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}

extern "C" int mlxc_lowered_value_and_grad(
    mlx_array* value_res,
    mlx_array* grad_res,
    const LoweredProgramInstr* program,
    size_t program_len,
    const uint32_t* refs,
    size_t refs_len,
    const mlx_array* consts,
    size_t consts_len,
    const mlx_array* inputs,
    size_t inputs_len,
    uint32_t root,
    uint32_t argnum) {
  try {
    if (!program || program_len == 0) {
      mlx_error("missing lowered program");
      return 1;
    }
    if (argnum >= inputs_len) {
      mlx_error("lowered argnum out of bounds");
      return 1;
    }

    std::vector<array> captured_consts;
    captured_consts.reserve(consts_len);
    for (size_t idx = 0; idx < consts_len; ++idx) {
      captured_consts.push_back(get_array_const(consts[idx]));
    }

    auto fun = [program, program_len, refs, refs_len, captured_consts, root](const std::vector<array>& call_inputs) {
      return execute_lowered_program(program, program_len, refs, refs_len, captured_consts, call_inputs, root);
    };

    std::vector<array> call_inputs;
    call_inputs.reserve(inputs_len);
    for (size_t idx = 0; idx < inputs_len; ++idx) {
      call_inputs.push_back(get_array_const(inputs[idx]));
    }

    auto vg = mlx::core::value_and_grad(fun, static_cast<int>(argnum));
    auto result = vg(call_inputs);
    if (value_res) {
      if (replace_array(value_res, result.first) != 0) {
        return 1;
      }
    }
    if (result.second.empty()) {
      mlx_error("lowered grad returned no gradients");
      return 1;
    }
    return replace_array(grad_res, result.second[0]);
  } catch (std::exception& e) {
    mlx_error(e.what());
    return 1;
  }
}
