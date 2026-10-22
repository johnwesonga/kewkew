defmodule Kewkew.Accounts do
  use Ash.Domain,
    otp_app: :kewkew

  resources do
    resource Kewkew.Accounts.Token
    resource Kewkew.Accounts.User
  end
end
