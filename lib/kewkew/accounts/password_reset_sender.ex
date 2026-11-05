defmodule Kewkew.Accounts.PasswordResetSender do
  @moduledoc "Sends password reset instructions to staff users."

  use AshAuthentication.Sender

  alias Kewkew.Mailer
  alias Swoosh.Email

  @impl true
  def send(user, token, _opts) do
    base_url = Application.fetch_env!(:kewkew, :public_base_url)
    link = base_url <> "/password-reset?" <> URI.encode_query(reset_token: token)

    Email.new()
    |> Email.to(to_string(user.email))
    |> Email.from({"Kewkew", "no-reply@kewkew.app"})
    |> Email.subject("Reset your Kewkew password")
    |> Email.text_body(
      "We received a request to reset your password. Use this link to choose a new one: #{link}\n\nIf you did not request this, you can ignore this email."
    )
    |> Mailer.deliver()

    :ok
  end
end
