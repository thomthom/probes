#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'sketchup.rb'


#-------------------------------------------------------------------------------

module TT::Plugins::Probes

  # Add some menu items to access this
  unless file_loaded?( __FILE__ )
    plugins_menu = UI.menu('Plugins')
    probes_menu = plugins_menu.add_submenu('Probes')
      probes_menu.add_item('Normals')   { self.probe(self::Probe_Normals) }
      probes_menu.add_item('UVs')       { self.probe(self::Probe_UV) }
      probes_menu.add_separator
      probes_menu.add_item('Count GC Materials')  { self.count_gc_materials }
  end

  # Constants
  unless file_loaded?( __FILE__ )
  POINT_OPEN_SQUARE     = 1
  POINT_FILLED_SQUARE   = 2
  POINT_CROSS           = 3
  POINT_X               = 4
  POINT_STAR            = 5
  POINT_OPEN_TRIANGLE   = 6
  POINT_FILLED_TRIANGLE = 7

  DICT_VRAY = '{DD17A615-9867-4806-8F46-B37031D7F153}'
  end

  # Shorthand to activate tools
  def self.probe(tool)
    Sketchup.active_model.select_tool(tool.new)
  end

  # Rounds a float to a given number of decimals and appends ~ to modified values.
  def self.format_float(float, round)
    formatted = (float*10**round).round.to_f/10**round
    tolerance = (float*10**(16-round)).round.to_f/10**(16-round)
    return (formatted == tolerance) ? formatted.to_s : '~' + formatted.to_s
  end


  ### MATERIALS ###
  def self.count_gc_materials
    # (!) Ignore V-Ray objects
    x = 0
    entities = []
    Sketchup.status_text = 'Counting Group & Component materials...'
    Sketchup.active_model.definitions.each { |d|
      d.instances.each { |i|
        # Ignore V-Ray Infinite Planes
        #next if i.get_attribute(DICT_VRAY, 'VRayForSketchUp_Marker') == 1
        # Ignore V-Ray Lights
        #next unless i.get_attribute(DICT_VRAY, 'light_type').nil?
        # Ignore all V-Ray objects
        next unless i.attribute_dictionary(DICT_VRAY).nil?
        unless i.material.nil?
          x += 1
          entities << i
        end
      }
    }
    str = "Groups and Components with material applied: #{x}"
    Sketchup.status_text = str
    Sketchup.active_model.selection.clear
    Sketchup.active_model.selection.add(entities)
    UI.messagebox(str)
  end


  class Probe_Normals

    def initialize
      @cursor_point = nil
      @entity = nil
      @ctrl = nil
    end

    def activate
      @cursor_point   = Sketchup::InputPoint.new
      @entity = nil

      @drawn = false

      Sketchup::set_status_text 'Hover over an Entity to see its normals. Click to reverse it. Pressing Ctrl will flip front/back materials'

      self.reset(nil)
    end

    def resume(view)
      Sketchup::set_status_text 'Hover over an Entity to see its normals. Click to reverse it. Pressing Ctrl will flip front/back materials'
    end

    def deactivate(view)
      view.invalidate if @drawn
    end

    def onMouseMove(flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      if ph.best_picked != @entity
        #view.invalidate
        @entity = ph.best_picked
      end
      @cursor_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonUp(flags, x, y, view)
      # Flip normals
      if @entity.is_a?(Sketchup::Face)
        view.model.start_operation( 'Flip Normals' )
        @entity.reverse!

        if @ctrl
          temp = @entity.material
          @entity.material = @entity.back_material
          @entity.back_material = temp
        end
        view.model.commit_operation
      end
    end

    def onKeyDown(key, repeat, flags, view)
      if key == VK_CONTROL && repeat == 1
        @ctrl = true
      end
    end

    def onKeyUp(key, repeat, flags, view)
      if key == VK_CONTROL #&& repeat == 1
        @ctrl = false
      end
    end

    def draw(view)
      if !@entity.nil? && @entity.valid?

        if @entity.is_a?(Sketchup::Edge)
          draw_edge(view, @entity)
          # Indicate start point
          view.draw_points(@entity.start.position, 8, POINT_X, 'purple')
        elsif @entity.is_a?(Sketchup::Face)
          @entity.edges.each { |e|
            draw_edge(view, e, @entity)
          }
          draw_normal(view, @cursor_point.position, @entity.normal, 50, 4.0)
        end

        @drawn = true
      end
    end


    def draw_edge(view, edge, face = nil)
      p1 = edge.start.position
      p2 = edge.end.position

      #view.line_width = 3.0
      #view.set_color_from_line(p1, p2)
      #view.draw_line(p1, p2)

      # Indicate start point
      #sp = Geom.linear_combination(0.2, p1, 0.8, p2)
      #view.line_width = 2.0
      #view.draw_points(sp, 8, POINT_X, 'purple')


      # Edge Normal
      reversed = (face.nil?) ? false : edge.reversed_in?(face)
      normal = edge.line[1]
      centre = Geom.linear_combination(0.5, p1, 0.5, p2)
      draw_normal(view, centre, normal, 20, 2.0, reversed)
    end


    # Draws an illustration of the given normal in 3D space
    def draw_normal(view, position, normal, pixels, thickness = 2.0, reversed = false)
      view.line_width = thickness

      size = view.pixels_to_model(pixels, position)

      type = (reversed) ? 1 : 2

      px = position.offset(normal.axes.x.transform(size))
      view.drawing_color = 'red'
      view.draw_line(position, px)
      view.draw_points(px, thickness * 2, type, 'red')

      py = position.offset(normal.axes.y.transform(size))
      view.drawing_color = 'green'
      view.draw_line(position, py)
      view.draw_points(py, thickness * 2, type, 'green')

      pz = position.offset(normal.axes.z.transform(size))
      view.drawing_color = 'blue'
      view.draw_line(position, pz)
      view.draw_points(pz, thickness * 2, type, 'blue')
    end

    # Reset the tool back to its initial state
    def reset(view)

      if view
        view.tooltip = nil
        view.invalidate if @drawn
      end

      @drawn = false
      @ctrl = false
    end
  end


  class Probe_UV

    def initialize
      @cursor_point = nil
      @entity = nil
      @ctrl = nil
      @shift = nil
      @polymesh = nil
      @path = nil
      @real_UV = nil
      @t = nil
    end

    def activate
      @cursor_point   = Sketchup::InputPoint.new
      @entity = nil
      @path = nil
      @t = nil

      @drawn = false

      Sketchup::set_status_text 'Hover over an Face to see its UVQ values.'

      self.reset(nil)
    end

    def deactivate(view)
      view.invalidate if @drawn
    end

    def onMouseMove(flags, x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)

      if @shift
        # Drill down through groups/components
        if ph.picked_face != @entity
          @entity = ph.picked_face
          @path = ph.path_at(0)
          @t = ph.transformation_at(0)
        end
      else
        # Pick only from active space
        if ph.best_picked != @entity
          @entity = ph.best_picked
        end
      end

      @cursor_point.pick(view, x, y)
      view.invalidate
    end

    def onLButtonUp(flags, x, y, view)
      # Flip normals
      if @entity.is_a?(Sketchup::Face)
        @entity.reverse!
      end
    end

    def onKeyUp(key, repeat, flags, view)
      if key == VK_CONTROL && repeat == 1
        @ctrl = !@ctrl
        view.invalidate
      end
      if key == VK_SHIFT && repeat == 1
        @shift = !@shift
        view.invalidate
      end
      if key == 9 && repeat == 1 # TAB
        @real_UV = !@real_UV
        view.invalidate
      end
      #if key == 113 && repeat == 1 # F2
      if key == 117 && repeat == 1 # F6
        @polymesh = !@polymesh
        view.invalidate
      end
      #puts key
    end

    def draw(view)
      if !@entity.nil? && @entity.valid?

        if @entity.is_a?(Sketchup::Face)
          # Get UV data
          tw = Sketchup.create_texture_writer
          uvHelp = @entity.get_UVHelper true, true, tw
          # Highlight the face edges.
          if @polymesh
            pm = @entity.mesh(7)
            pm.polygons.each { |poly|
              points = poly.collect { |p| pm.point_at(p) }
              view.line_width = 3.0
              view.drawing_color = 'yellow'
              view.draw(GL_LINE_LOOP, points)
            }
          else
            @entity.edges.each { |e|
              draw_edge(view, e)
            }
          end
          # Iterate each vertex and display UV values
          if @polymesh
            vertices = pm.points
          else
            vertices = @entity.vertices.to_a.collect { |v| v.position }
          end
          vertices.each_index { |i|
            v = vertices[i]
            if @ctrl
              if @polymesh
                uv = pm.uvs(false)[i]
              else
                uv = uvHelp.get_back_UVQ(v)
              end
            else
              if @polymesh
                uv = pm.uvs(true)[i]
              else
                uv = uvHelp.get_front_UVQ(v)
              end
            end
            # Mark the vertices
            pos = (@shift) ? global_position(v) : v
            view.draw_points(pos, 6, POINT_FILLED_SQUARE, 'yellow')
            # Get Screen co-ordinates of the point and adjust XY for text position
            xy = view.screen_coords(pos)
            xy.x -= 60
            xy.y += 5
            # Draw the text
            view.drawing_color = 'purple'
            view.draw_text(xy, "Testing") # (!) This is not drawn for some reason. If this is removed the next line doesn't draw.
            # (!) Output real UV data.
            if @real_UV
              view.draw_text(xy, "(##{i}) UV: #{TT_Probes.format_float(uv.x/uv.z,3)}, #{TT_Probes.format_float(uv.y/uv.z,3)}")
            else
              view.draw_text(xy, "(##{i}) UVHelper Raw Data: #{TT_Probes.format_float(uv.x,3)}, #{TT_Probes.format_float(uv.y,3)}, #{TT_Probes.format_float(uv.z,3)}")
            end
          }
        end

        @drawn = true
      end

      # Indicate which side we pick from
      if @ctrl
        view.draw_text([10,10,0], 'Backface UV')
      else
        view.draw_text([10,10,0], 'Frontface UV')
      end

      # Indicate the scope of picking
      if @shift
        view.draw_text([10,30,0], 'Picking face from whole model...')
      else
        view.draw_text([10,30,0], 'Picking face from active space only...')
      end

      # Indicate the scope of picking
      if @real_UV
        view.draw_text([10,50,0], 'Real UV Coordinates')
      else
        view.draw_text([10,50,0], 'Raw UVHelper data')
      end

      # Display the drill down path
      unless @path.nil?
        view.draw_text([10,70,0], @path.inspect)
      end

      # Indicate the scope of picking
      if @polymesh
        view.draw_text([10,90,0], 'Polymesh')
      end
    end

    def draw_edge(view, edge)
      p1 = (@shift) ? global_position(edge.start.position) : edge.start.position
      p2 = (@shift) ? global_position(edge.end.position) : edge.end.position

      view.line_width = 3.0
      view.drawing_color = 'yellow'
      view.draw_line(p1, p2)
    end

    # Get the global position with the help of the path list from the PickHelper.
    def global_position(point)
      #puts @t
      point.transform!(@t) unless @t.nil?
      return point

      return point if @path.nil?
      @path.each { |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        point.transform!(e.transformation)
      }
      return point
    end

    # Reset the tool back to its initial state
    def reset(view)

      if view
        view.tooltip = nil
        view.invalidate if @drawn
      end

      @drawn = false
      @ctrl = false
      @shift = false
      @polymesh = false
      @real_UV = true
    end
  end

end # module

#-------------------------------------------------------------------------------

file_loaded( __FILE__ )

#-------------------------------------------------------------------------------