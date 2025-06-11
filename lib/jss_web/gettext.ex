defmodule JSSWeb.Gettext do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://hexdocs.pm/gettext),
  your module gains a set of macros for translations, for example:

      import JSSWeb.Gettext

      # Simple translation
      gettext("Here is the string to translate")

      # Plural translation
      ngettext("Here is the string to translate",
               "Here are the strings to translate",
               3)

      # Domain-based translation
      dgettext("errors", "Here is the error message to translate")

  See the [Gettext Docs](https://hexdocs.pm/gettext) for detailed usage.
  """

  # Fallback si gettext n'est pas disponible
  try do
    use Gettext, otp_app: :jss
  rescue
    UndefinedFunctionError ->
      # Fallback functions when gettext is not available
      defmacro gettext(msgid) do
        quote do: unquote(msgid)
      end

      defmacro ngettext(msgid, msgid_plural, n) do
        quote do
          if unquote(n) == 1 do
            unquote(msgid)
          else
            unquote(msgid_plural)
          end
        end
      end

      defmacro dgettext(_domain, msgid) do
        quote do: unquote(msgid)
      end
  end
end
