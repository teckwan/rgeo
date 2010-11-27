# -----------------------------------------------------------------------------
# 
# Well-known binary parser for RGeo
# 
# -----------------------------------------------------------------------------
# Copyright 2010 Daniel Azuma
# 
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of the copyright holder, nor the names of any other
#   contributors to this software, may be used to endorse or promote products
#   derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
# -----------------------------------------------------------------------------
;


module RGeo
  
  module WKRep
    
    
    # This class provides the functionality of parsing a geometry from
    # WKB (well-known binary) format. You may also customize the parser
    # to recognize PostGIS EWKB extensions to the input, or Simple
    # Features Specification 1.2 extensions for Z and M coordinates.
    # 
    # To use this class, create an instance with the desired settings and
    # customizations, and call the parse method.
    # 
    # === Configuration options
    # 
    # The following options are recognized. These can be passed to the
    # constructor, or set on the object afterwards.
    # 
    # <tt>:default_factory</tt>::
    #   The default factory for parsed geometries, used when no factory
    #   generator is provided. If no default is provided either, the
    #   default cartesian factory will be used as the default.
    # <tt>:factory_generator</tt>::
    #   A factory generator that should return a factory based on the
    #   srid and dimension settings in the input. The factory generator
    #   should understand the configuration options <tt>:srid</tt>,
    #   <tt>:support_z_coordinate</tt>, and <tt>:support_m_coordinate</tt>.
    #   See RGeo::Feature::FactoryGenerator for more information.
    #   If no generator is provided, the <tt>:default_factory</tt> is
    #   used.
    # <tt>:support_ewkb</tt>::
    #   Activate support for PostGIS EWKB type codes, which use high
    #   order bits in the type code to signal the presence of Z, M, and
    #   SRID values in the data. Default is false.
    # <tt>:support_wkb12</tt>::
    #   Activate support for SFS 1.2 extensions to the type codes, which
    #   use values greater than 1000 to signal the presence of Z and M
    #   values in the data. SFS 1.2 types such as triangle, tin, and
    #   polyhedralsurface are NOT yet supported. Default is false.
    # <tt>:ignore_extra_bytes</tt>::
    #   If true, extra bytes at the end of the data are ignored. If
    #   false (the default), extra bytes will trigger a parse error.
    
    class WKBParser
      
      
      # Create and configure a WKB parser. See the WKBParser
      # documentation for the options that can be passed.
      
      def initialize(opts_={})
        @default_factory = opts_[:default_factory] || Cartesian.preferred_factory
        @factory_generator = opts_[:factory_generator]
        @support_ewkb = opts_[:support_ewkb] ? true : false
        @support_wkb12 = opts_[:support_wkb12] ? true : false
        @ignore_extra_bytes = opts_[:ignore_extra_bytes] ? true : false
      end
      
      
      # Returns the default factory. See WKBParser for details.
      def default_factory
        @default_factory
      end
      
      # Sets the default factory. See WKBParser for details.
      def default_factory=(value_)
        @default_factory = value_ || Cartesian.preferred_factory
      end
      
      # Returns the factory generator, or nil if there is none.
      # See WKBParser for details.
      def factory_generator
        @factory_generator
      end
      
      # Sets the factory_generator. See WKBParser for details.
      def factory_generator=(value_)
        @factory_generator = value_
      end
      
      # Sets the factory_generator to the given block.
      # See WKBParser for details.
      def to_generate_factory(&block_)
        @factory_generator = block_
      end
      
      # Returns true if this parser supports EWKB.
      # See WKBParser for details.
      def support_ewkb?
        @support_ewkb
      end
      
      # Sets the the support_ewkb flag. See WKBParser for details.
      def support_ewkb=(value_)
        @support_ewkb = value_ ? true : false
      end
      
      # Returns true if this parser supports SFS 1.2 extensions.
      # See WKBParser for details.
      def support_wkb12?
        @support_wkb12
      end
      
      # Sets the the support_wkb12 flag. See WKBParser for details.
      def support_wkb12=(value_)
        @support_wkb12 = value_ ? true : false
      end
      
      # Returns true if this parser ignores extra bytes.
      # See WKBParser for details.
      def ignore_extra_bytes?
        @ignore_extra_bytes
      end
      
      # Sets the the ignore_extra_bytes flag. See WKBParser for details.
      def ignore_extra_bytes=(value_)
        @ignore_extra_bytes = value_ ? true : false
      end
      
      
      # Parse the given hex string, and return a geometry object.
      
      def parse_hex(str_)
        parse([str_].pack('H*'))
      end
      
      
      # Parse the given binary data, and return a geometry object.
      
      def parse(data_)
        @cur_has_z = nil
        @cur_has_m = nil
        @cur_srid = nil
        @cur_dims = 2
        @cur_factory = @default_factory
        begin
          _start_scanner(data_)
          obj_ = _parse_object(false)
          unless @ignore_extra_bytes
            bytes_ = _bytes_remaining
            if bytes_ > 0
              raise Error::ParseError, "Found #{bytes_} extra bytes at the end of the stream."
            end
          end
        ensure
          _clean_scanner
        end
        obj_
      end
      
      
      def _parse_object(contained_)  # :nodoc:
        little_endian_ = _get_byte == 1
        type_code_ = _get_integer(little_endian_)
        has_z_ = false
        has_m_ = false
        srid_ = nil
        if @support_ewkb
          has_z_ ||= type_code_ & 0x80000000 != 0
          has_m_ ||= type_code_ & 0x40000000 != 0
          srid_ = _get_integer(little_endian_) if type_code_ & 0x20000000 != 0
          type_code_ &= 0x0fffffff
        end
        if @support_wkb12
          has_z_ ||= (type_code_ / 1000) & 1 != 0
          has_m_ ||= (type_code_ / 1000) & 2 != 0
          type_code_ %= 1000
        end
        if contained_
          if contained_ != true && contained_ != type_code_
            raise Error::ParseError, "Enclosed type=#{type_code_} is different from container constraint #{contained_}"
          end
          if has_z_ != @cur_has_z
            raise Error::ParseError, "Enclosed hasZ=#{has_z_} is different from toplevel hasZ=#{@cur_has_z}"
          end
          if has_m_ != @cur_has_m
            raise Error::ParseError, "Enclosed hasM=#{has_m_} is different from toplevel hasM=#{@cur_has_m}"
          end
          if srid_ && srid_ != @cur_srid
            raise Error::ParseError, "Enclosed SRID #{srid_} is different from toplevel srid #{@cur_srid || '(unspecified)'}"
          end
        else
          @cur_has_z = has_z_
          @cur_has_m = has_m_
          @cur_dims = 2 + (@cur_has_z ? 1 : 0) + (@cur_has_m ? 1 : 0)
          @cur_srid = srid_.to_i
          if @factory_generator
            @cur_factory = @factory_generator.call(:srid => @cur_srid, :support_z_coordinate => has_z_, :support_m_coordinate => has_m_)
          end
          if @cur_has_z && !@cur_factory.has_capability?(:z_coordinate)
            raise Error::ParseError, "Data has Z coordinates but the factory doesn't have z_coordinate capability"
          end
          if @cur_has_m && !@cur_factory.has_capability?(:m_coordinate)
            raise Error::ParseError, "Data has M coordinates but the factory doesn't have m_coordinate capability"
          end
        end
        case type_code_
        when 1
          coords_ = _get_doubles(little_endian_, @cur_dims)
          @cur_factory.point(*coords_)
        when 2
          _parse_line_string(little_endian_)
        when 3
          interior_rings_ = (1.._get_integer(little_endian_)).map{ _parse_line_string(little_endian_) }
          exterior_ring_ = interior_rings_.shift || @cur_factory.linear_ring([])
          @cur_factory.polygon(exterior_ring_, interior_rings_)
        when 4
          @cur_factory.multi_point((1.._get_integer(little_endian_)).map{ _parse_object(1) })
        when 5
          @cur_factory.multi_line_string((1.._get_integer(little_endian_)).map{ _parse_object(2) })
        when 6
          @cur_factory.multi_polygon((1.._get_integer(little_endian_)).map{ _parse_object(3) })
        when 7
          @cur_factory.collection((1.._get_integer(little_endian_)).map{ _parse_object(true) })
        else
          raise Error::ParseError, "Unknown type value: #{type_code_}."
        end
      end
      
      
      def _parse_line_string(little_endian_)  # :nodoc:
        count_ = _get_integer(little_endian_)
        coords_ = _get_doubles(little_endian_, @cur_dims * count_)
        @cur_factory.line_string((0...count_).map{ |i_| @cur_factory.point(*coords_[@cur_dims*i_,@cur_dims]) })
      end
      
      
      def _start_scanner(data_)  # :nodoc:
        @_data = data_
        @_len = data_.length
        @_pos = 0
      end
      
      
      def _clean_scanner  # :nodoc:
        @_data = nil
      end
      
      
      def _bytes_remaining  # :nodoc:
        @_len - @_pos
      end
      
      
      def _get_byte  # :nodoc:
        if @_pos + 1 > @_len
          raise Error::ParseError, "Not enough bytes left to fulfill 1 byte"
        end
        str_ = @_data[@_pos, 1]
        @_pos += 1
        str_.unpack("C").first
      end
      
      
      def _get_integer(little_endian_)  # :nodoc:
        if @_pos + 4 > @_len
          raise Error::ParseError, "Not enough bytes left to fulfill 1 integer"
        end
        str_ = @_data[@_pos, 4]
        @_pos += 4
        str_.unpack("#{little_endian_ ? 'V' : 'N'}").first
      end
      
      
      def _get_doubles(little_endian_, count_)  # :nodoc:
        len_ = 8 * count_
        if @_pos + len_ > @_len
          raise Error::ParseError, "Not enough bytes left to fulfill #{count_} doubles"
        end
        str_ = @_data[@_pos, len_]
        @_pos += len_
        str_.unpack("#{little_endian_ ? 'E' : 'G'}*")
      end
      
      
    end
    
    
  end
  
end
