class Scrape
  require 'ferrum'

  # 1. Defina a URL que deseja acessar e o nome do arquivo de saída
  url = 'https://atsu.moe/manga/CM0wz'
  output_file = 'berserk.html'

  # 2. Inicializa uma nova instância do navegador Chrome
  browser = Ferrum::Browser.new(timeout: 15)

  begin
    # 3. Navega até a URL desejada
    browser.go_to(url)

    # Opcional: Aguarda a rede ficar ociosa (útil para páginas pesadas em JavaScript)
    browser.network.wait_for_idle

    # 4. Obtém o HTML atual da página após a renderização do JS
    html_content = browser.body

    # 5. Salva o conteúdo extraído no arquivo local
    File.write(output_file, html_content)
    # 6. Garante que o processo do Chrome seja encerrado corretamente
    browser.quit
  end
end
