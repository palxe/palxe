defmodule Palxe.Place.Palette do
  @moduledoc "The fixed 32-color palette. Pixels store the index into this list."

  @colors ~w(
    #6D001A #BE0039 #FF4500 #FFA800 #FFD635 #FFF8B8 #00A368 #00CC78
    #7EED56 #00756F #009EAA #00CCC0 #2450A4 #3690EA #51E9F4 #493AC1
    #6A5CFF #94B3FF #811E9F #B44AC0 #E4ABFF #DE107F #FF3881 #FF99AA
    #6D482F #9C6926 #FFB470 #000000 #515252 #898D90 #D4D7D9 #FFFFFF
  )

  @size length(@colors)
  @white @size - 1

  def colors, do: @colors
  def size, do: @size
  def white, do: @white

  def hex(index) when is_integer(index) and index >= 0 and index < @size,
    do: Enum.at(@colors, index)

  def valid?(index), do: is_integer(index) and index >= 0 and index < @size
end
