[CmdletBinding()]
param([string]$Destination, [string]$PayloadRoot, [switch]$NoLaunch, [switch]$NoUI)
$ErrorActionPreference = 'Stop'
function Set-Utf8File([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}
function Copy-Preserve([string]$Source,[string]$Target) {
    if (Test-Path -LiteralPath $Target) {
        if ((Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash) { return }
        $candidate = $Target + '.actualizacion-publica'
        Copy-Item -LiteralPath $Source -Destination $candidate -Force
    } else { Copy-Item -LiteralPath $Source -Destination $Target }
}
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not $Destination) { $Destination=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Asistente de Prensa - Enrique' }
    $Destination=[IO.Path]::GetFullPath($Destination)
    if (-not $PayloadRoot) {
        $cache=Join-Path ([IO.Path]::GetTempPath()) ('prensa-setup-'+[Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $cache | Out-Null
        $archive=Join-Path $cache 'publico.zip'
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Alex00111001/prensa/main/descargas/materiales_publicos.zip' -OutFile $archive -UseBasicParsing
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip=[IO.Compression.ZipFile]::OpenRead($archive)
        try {
            foreach($entry in $zip.Entries) {
                $resolved=[IO.Path]::GetFullPath((Join-Path $cache $entry.FullName))
                if(-not $resolved.StartsWith($cache+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'El paquete contiene una ruta no permitida.' }
            }
        } finally { $zip.Dispose() }
        Expand-Archive -LiteralPath $archive -DestinationPath $cache
        $PayloadRoot=Join-Path $cache 'materiales'
    }
    $PayloadRoot=[IO.Path]::GetFullPath($PayloadRoot)
    $manifest=Get-Content -LiteralPath (Join-Path $PayloadRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($entry in $manifest.PSObject.Properties) {
        $file=[IO.Path]::GetFullPath((Join-Path $PayloadRoot $entry.Name))
        if(-not $file.StartsWith($PayloadRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta de manifiesto no permitida.' }
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) { throw ('Archivo incompleto o modificado: '+$entry.Name) }
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $tasks=@('Notas de prensa','Intervenciones y discursos')
    foreach($task in $tasks) {
        $taskRoot=Join-Path $Destination $task
        foreach($scope in @('Institucional','Partidista')) {
            foreach($folder in @('Material de aprendizaje','Fuentes de trabajo','Borradores','Aprobados','Preferencias confirmadas')) {
                New-Item -ItemType Directory -Path (Join-Path (Join-Path $taskRoot $scope) $folder) -Force | Out-Null
            }
        }
        foreach($folder in @('Pendiente de clasificacion','Configuracion publica','Fuentes privadas')) { New-Item -ItemType Directory -Path (Join-Path $taskRoot $folder) -Force | Out-Null }
        $config=Join-Path $taskRoot 'Configuracion publica'
        $stem=if($task -eq 'Notas de prensa'){'Notas_de_prensa'}else{'Intervenciones_y_discursos'}
        Copy-Preserve (Join-Path $PayloadRoot ('instrucciones/'+$stem+'.txt')) (Join-Path $config 'Instrucciones_del_proyecto.txt')
        Copy-Preserve (Join-Path $PayloadRoot ('prompts/'+$stem+'.txt')) (Join-Path $config 'Prompt_maestro.txt')
        Copy-Preserve (Join-Path $PayloadRoot 'Bienvenida.txt') (Join-Path $config 'Bienvenida.txt')
        foreach($name in @('Anexo_operativo.md','Contexto_y_fuentes.md','Aprendizaje_progresivo.md')) { Copy-Preserve (Join-Path $PayloadRoot ('plantillas/'+$name)) (Join-Path $config $name) }
        $privateReadme=Join-Path (Join-Path $taskRoot 'Fuentes privadas') 'LEEME.txt'
        if(-not(Test-Path -LiteralPath $privateReadme)) { Set-Utf8File $privateReadme 'Los documentos originales de Enrique NO se incluyen en la descarga publica. Copialos desde su Drive privado autorizado, incluido Documento_Maestro_Requisitos_Enrique_Garcia.docx. No publiques estos archivos. Las plantillas de Configuracion publica son genericas y no sustituyen el contexto privado.' }
    }
    $stateFile=Join-Path $Destination 'estado_instalacion_local.json'
    $state=@{version=2;archivos_publicos='verificados';carpetas='creadas_localmente';drive='pendiente';proyectos_chatgpt='pendientes';documentos_privados='no_descargados';fecha=(Get-Date).ToString('s')}
    if(Test-Path -LiteralPath $stateFile) {
        try { $previous=Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8|ConvertFrom-Json; foreach($key in @('drive','proyectos_chatgpt','documentos_privados')) { if($previous.$key){$state[$key]=$previous.$key} } } catch { }
    }
    $launch='no_solicitado'
    if(-not $NoLaunch) {
        $apps=@(Get-StartApps | Where-Object { $_.Name -eq 'ChatGPT' })
        if($apps.Count -eq 1) {
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:AppsFolder\'+$apps[0].AppID)
            $launch='solicitud_enviada'
        } else { $launch='no_detectado_o_ambiguo' }
    }
    $state['chatgpt_desktop']=$launch
    Set-Utf8File $stateFile ($state|ConvertTo-Json -Depth 5)
    $summary="Preparacion local terminada.`n`nArchivos publicos descargados y comprobados.`nCarpetas creadas en: $Destination`n`nLos proyectos de ChatGPT, Drive y los documentos privados siguen pendientes. El script no ha iniciado sesion ni creado carpetas en Drive."
    if($launch -eq 'solicitud_enviada'){$summary+="`n`nSe ha solicitado abrir ChatGPT de escritorio. Comprueba que aparece e inicia sesion."}
    if($launch -eq 'no_detectado_o_ambiguo'){$summary+="`n`nChatGPT de escritorio no se ha podido identificar. Abre la aplicacion instalada desde Inicio; no se abrira ChatGPT web como sustituto."}
    if(-not $NoUI) { Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show($summary,'Preparacion de Enrique')|Out-Null }
    Write-Output $summary
} catch {
    $message='No se ha completado la preparacion: '+$_.Exception.Message
    if(-not $NoUI){Add-Type -AssemblyName System.Windows.Forms;[Windows.Forms.MessageBox]::Show($message,'Revisar instalacion')|Out-Null}
    Write-Error $message
    exit 1
}
